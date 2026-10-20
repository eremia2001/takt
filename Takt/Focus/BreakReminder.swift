import Foundation
import Observation
import os
import TaktCore
import UserNotifications

/// Kennungen außerhalb der MainActor-Klasse, damit auch die nicht isolierten
/// Delegate-Methoden sie lesen dürfen.
private enum BreakReminderID {
    static let request = "dev.eremiya.takt.break-reminder"
    static let entryKey = "entryId"
}

/// Kennungen der Mitteilung zum geplanten Block („Geplant: Kundenportal um 14:00“).
private enum PlannedBlockID {
    static let request = "dev.eremiya.takt.planned-block"
    static let category = "dev.eremiya.takt.planned-block"
    static let startAction = "planned.start"
    static let blockKey = "blockId"
}

/// Plant pro Timer-Lauf genau eine lokale Mitteilung „Kurze Pause?“ und pausiert beim
/// Auslösen auf Wunsch die Musik. Außerdem: Mitteilung zum geplanten Block, wenn dessen Beginn
/// erreicht ist und kein Timer läuft (Aktion „Starten“).
@MainActor
@Observable
final class BreakReminder: NSObject, UNUserNotificationCenterDelegate {
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let musicController: MusicController
    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    /// Aktueller Timer-Lauf (nil = nichts läuft).
    @ObservationIgnored private var current: RunningState?
    /// Eintrag, für den die Erinnerung bereits ausgelöst hat – pro Lauf nur einmal.
    @ObservationIgnored private var firedEntryId: UUID?
    /// Interner Wecker zur Auslösezeit. Nötig, weil macOS `willPresent` nur aufruft, wenn die
    /// App im Vordergrund ist, und `didReceive` erst beim Klick auf die Mitteilung.
    @ObservationIgnored private var fireTask: Task<Void, Never>?
    /// Verhindert, dass ein verspätetes `add` eine inzwischen aufgehobene Mitteilung zurückbringt.
    @ObservationIgnored private var scheduleToken = 0

    /// Geplanter Block samt Projektname (vom Store gemeldet).
    @ObservationIgnored private var plannedBlock: PlannedBlock?
    @ObservationIgnored private var plannedProjectName: String?
    /// Wie `scheduleToken`, für die Mitteilung zum geplanten Block.
    @ObservationIgnored private var plannedToken = 0
    /// Aktion „Starten“ der Mitteilung zum geplanten Block; der Store setzt sie in `attach`.
    /// Übergeben wird die ID des Blocks, damit eine veraltete Mitteilung nichts startet.
    @ObservationIgnored var startPlannedBlock: ((UUID) -> Void)?

    private static let logger = Logger(subsystem: "dev.eremiya.takt", category: "focus")

    init(settings: AppSettings, musicController: MusicController) {
        self.settings = settings
        self.musicController = musicController
        super.init()
        center.delegate = self
    }

    // MARK: Öffentliche Schnittstelle

    /// Vom Store bei jedem Wechsel des laufenden Eintrags aufgerufen.
    func timerDidChange(from old: RunningState?, to new: RunningState?) {
        current = new
        reschedule()
        reschedulePlanned()
    }

    /// Beim App-Start: Zustand übernehmen, ohne dass das als Timer-Start zählt.
    /// Liegt die Auslösezeit noch in der Zukunft, wird die Mitteilung (neu) geplant.
    func resume(with running: RunningState?) {
        current = running
        reschedule()
        reschedulePlanned()
    }

    /// Vom Store, wenn der geplante Block gesetzt, geändert oder entfernt wurde.
    func plannedBlockDidChange(_ block: PlannedBlock?, projectName: String?) {
        plannedBlock = block
        plannedProjectName = projectName
        reschedulePlanned()
    }

    /// Nach Änderungen an den Pausen-Einstellungen aufrufen.
    func settingsDidChange() {
        reschedule()
    }

    // MARK: Planung

    private func reschedule() {
        cancelPending()
        guard settings.breakReminderEnabled, let current, firedEntryId != current.entry.id else { return }

        let duration = TimeInterval(settings.breakReminderMinutes * 60)
        // Ab Beginn des Eintrags rechnen – Starts aus dem Widget können etwas zurückliegen.
        let fireDate = current.entry.startedAt.addingTimeInterval(duration)
        let delay = fireDate.timeIntervalSinceNow
        guard delay > 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Kurze Pause?"
        content.body = "Du arbeitest seit \(DurationFormat.hourMinute(duration)) an \(current.project.name)."
        content.sound = .default
        content.userInfo = [BreakReminderID.entryKey: current.entry.id.uuidString]

        let request = UNNotificationRequest(
            identifier: BreakReminderID.request,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        )

        let token = scheduleToken
        Task {
            await requestAuthorizationIfNeeded()
            guard token == scheduleToken else { return }
            do {
                try await center.add(request)
                // Während des Hinzufügens gestoppt? Dann gleich wieder entfernen.
                if token != scheduleToken {
                    center.removePendingNotificationRequests(withIdentifiers: [BreakReminderID.request])
                }
            } catch {
                Self.logger.error("Pausenerinnerung nicht geplant: \(error.localizedDescription, privacy: .public)")
            }
        }

        let entryId = current.entry.id
        fireTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.didFire(entryId: entryId)
        }
        Self.logger.info("Pausenerinnerung in \(Int(delay / 60)) Min geplant.")
    }

    /// Plant „Geplant: … um 14:00“ zum Beginn des Blocks – nur wenn bis dahin nichts läuft.
    /// Jeder Timer-Wechsel plant neu: Startet vorher ein Timer, entfällt die Mitteilung;
    /// wird er vor dem Beginn wieder gestoppt, ist sie erneut geplant.
    private func reschedulePlanned() {
        plannedToken += 1
        center.removePendingNotificationRequests(withIdentifiers: [PlannedBlockID.request])
        // Erledigt (Block weg oder Timer läuft): auch eine schon zugestellte Mitteilung entfernen.
        if plannedBlock == nil || current != nil {
            center.removeDeliveredNotifications(withIdentifiers: [PlannedBlockID.request])
        }
        guard let block = plannedBlock, let name = plannedProjectName, current == nil else { return }
        let delay = block.startAt.timeIntervalSinceNow
        guard delay > 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Geplant: \(name) um \(ClockFormat.time(block.startAt))"
        content.body = block.note ?? "Jetzt starten?"
        content.sound = .default
        content.categoryIdentifier = PlannedBlockID.category
        content.userInfo = [PlannedBlockID.blockKey: block.id.uuidString]

        let request = UNNotificationRequest(
            identifier: PlannedBlockID.request,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        )

        let token = plannedToken
        let center = center
        Task {
            await requestAuthorizationIfNeeded()
            await Self.registerPlannedCategory(center)
            guard token == plannedToken else { return }
            do {
                try await center.add(request)
                if token != plannedToken {
                    center.removePendingNotificationRequests(withIdentifiers: [PlannedBlockID.request])
                }
            } catch {
                Self.logger.error("Mitteilung zum geplanten Block nicht geplant: \(error.localizedDescription, privacy: .public)")
            }
        }
        Self.logger.info("Mitteilung zum geplanten Block in \(Int(delay / 60)) Min geplant.")
    }

    /// Registriert die Kategorie mit der Aktion „Starten“, ohne andere Kategorien zu verlieren.
    /// `ForgottenTimerGuard` registriert seine beim App-Start ebenfalls per Lesen-und-Ergänzen;
    /// laufen beide gleichzeitig, kann eine Kategorie verloren gehen – daher kurz nachprüfen.
    private static func registerPlannedCategory(_ center: UNUserNotificationCenter) async {
        let category = UNNotificationCategory(
            identifier: PlannedBlockID.category,
            actions: [UNNotificationAction(identifier: PlannedBlockID.startAction, title: "Starten")],
            intentIdentifiers: []
        )
        for _ in 0..<3 {
            var categories = await center.notificationCategories()
            if categories.contains(where: { $0.identifier == PlannedBlockID.category }) { return }
            categories.insert(category)
            center.setNotificationCategories(categories)
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func cancelPending() {
        scheduleToken += 1
        fireTask?.cancel()
        fireTask = nil
        center.removePendingNotificationRequests(withIdentifiers: [BreakReminderID.request])
    }

    private func requestAuthorizationIfNeeded() async {
        let status = await center.notificationSettings().authorizationStatus
        guard status == .notDetermined else { return }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            Self.logger.info("Mitteilungen \(granted ? "erlaubt" : "abgelehnt", privacy: .public).")
        } catch {
            Self.logger.error("Mitteilungs-Berechtigung fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Auslösung – egal ob über den internen Wecker oder den Delegate; wirkt pro Lauf nur einmal.
    private func didFire(entryId: UUID?) {
        guard let entryId, entryId == current?.entry.id, firedEntryId != entryId else { return }
        firedEntryId = entryId
        fireTask = nil
        Self.logger.info("Pausenerinnerung ausgelöst.")
        if settings.breakPausesMusic {
            musicController.pauseForBreak()
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// App im Vordergrund: trotzdem als Banner zeigen.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Geplanter Block: nur anzeigen, keine Pausen-Auslösung.
        if notification.request.identifier != PlannedBlockID.request {
            let entryId = Self.entryId(of: notification)
            Task { @MainActor in self.didFire(entryId: entryId) }
        }
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Nachfrage „vergessener Timer“ gehört nicht hierher: an ForgottenTimerGuard weiterreichen.
        if ForgottenTimerGuard.handles(response.notification) {
            ForgottenTimerGuard.handleNotificationResponse(response)
            completionHandler()
            return
        }
        if response.notification.request.identifier == PlannedBlockID.request {
            // „Starten“ startet das Projekt des Blocks; ein Klick auf die Mitteilung öffnet nur Takt.
            if response.actionIdentifier == PlannedBlockID.startAction,
               let text = response.notification.request.content.userInfo[PlannedBlockID.blockKey] as? String,
               let blockId = UUID(uuidString: text) {
                Task { @MainActor in self.startPlannedBlock?(blockId) }
            }
            completionHandler()
            return
        }
        let entryId = Self.entryId(of: response.notification)
        Task { @MainActor in self.didFire(entryId: entryId) }
        completionHandler()
    }

    private nonisolated static func entryId(of notification: UNNotification) -> UUID? {
        guard notification.request.identifier == BreakReminderID.request,
              let text = notification.request.content.userInfo[BreakReminderID.entryKey] as? String
        else { return nil }
        return UUID(uuidString: text)
    }
}
