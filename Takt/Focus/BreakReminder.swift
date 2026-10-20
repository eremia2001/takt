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

/// Plant pro Timer-Lauf genau eine lokale Mitteilung „Kurze Pause?“ und pausiert beim
/// Auslösen auf Wunsch die Musik.
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
    }

    /// Beim App-Start: Zustand übernehmen, ohne dass das als Timer-Start zählt.
    /// Liegt die Auslösezeit noch in der Zukunft, wird die Mitteilung (neu) geplant.
    func resume(with running: RunningState?) {
        current = running
        reschedule()
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
        let entryId = Self.entryId(of: notification)
        Task { @MainActor in self.didFire(entryId: entryId) }
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
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
