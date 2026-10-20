import AppKit
import Foundation
import os
import TaktCore
import UserNotifications

/// Fragt nach, wenn ein Timer länger als `forgottenTimerHours` läuft – einmal pro Eintrag.
/// Nach „Läuft weiter“ frühestens nach weiteren 2 Stunden erneut.
///
/// App aktiv → `NSAlert` (als Sheet am Hauptfenster), sonst eine Mitteilung mit denselben
/// Aktionen. Antworten auf die Mitteilung kommen über das Delegate von `BreakReminder`
/// (`UNUserNotificationCenter` hat nur ein Delegate) und landen in `handleNotificationResponse`.
@MainActor
final class ForgottenTimerGuard {
    private let store: TaktStore
    private let settings: AppSettings
    private let center = UNUserNotificationCenter.current()

    /// Einträge, zu denen schon gefragt wurde (Alert gezeigt oder Mitteilung zugestellt).
    private var askedEntryIds: Set<UUID> = []
    /// Nach „Läuft weiter“: frühestens ab diesem Zeitpunkt erneut fragen.
    private var snoozedUntil: [UUID: Date] = [:]
    /// Verhindert einen zweiten Alert, solange einer offen ist.
    private var isAlertShown = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    /// Wartezeit nach „Läuft weiter“.
    static let snoozeInterval: TimeInterval = 2 * 3600
    private static let checkInterval: TimeInterval = 60

    /// Für die Weiterleitung aus dem Notification-Delegate.
    private static weak var current: ForgottenTimerGuard?
    private static let logger = Logger(subsystem: "dev.eremiya.takt", category: "focus")

    init(store: TaktStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        Self.current = self
        // Die Kategorie mit den Aktionen registriert `NotificationCategories.register()` beim App-Start.

        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Der Store lädt beim Aktivwerden ebenfalls neu; erst danach prüfen.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.check() } }
        })
        observers.append(center.addObserver(
            forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Beim Start kurz warten, bis das Hauptfenster steht (für das Sheet).
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                MainActor.assumeIsolated { self?.check() }
            }
        })
    }

    // MARK: Prüfung

    /// Prüft den laufenden Eintrag und fragt bei Bedarf nach.
    func check(now: Date = .now) {
        guard let running = store.running else { return }
        let entryId = running.entry.id
        let limit = TimeInterval(settings.forgottenTimerHours) * 3600
        guard now.timeIntervalSince(running.entry.startedAt) >= limit,
              !askedEntryIds.contains(entryId),
              now >= snoozedUntil[entryId] ?? .distantPast,
              !isAlertShown
        else { return }

        askedEntryIds.insert(entryId)
        if NSApp.isActive {
            showAlert(for: running, now: now)
        } else {
            postNotification(for: running, now: now)
        }
    }

    // MARK: Antworten

    private enum Answer {
        case keepRunning, stopNow, stopAt
    }

    private func handle(_ answer: Answer, entryId: UUID) {
        removeNotification()
        // Inzwischen anderswo gestoppt (Widget, Menüleiste)? Dann nichts tun.
        guard store.running?.entry.id == entryId else { return }
        switch answer {
        case .keepRunning:
            askedEntryIds.remove(entryId)
            snoozedUntil[entryId] = Date.now.addingTimeInterval(Self.snoozeInterval)
        case .stopNow:
            store.stop(nextStep: nil)
        case .stopAt:
            // Jetzt stoppen und „Heute“ zeigen; dort korrigiert der Nutzer das Ende im Eintrag.
            store.stop(nextStep: nil)
            MenuBarController.showToday()
        }
    }

    // MARK: Alert

    private func showAlert(for running: RunningState, now: Date) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Läuft ‚\(running.project.name)‘ wirklich noch?"
        alert.informativeText = Self.detail(for: running, now: now)
        alert.addButton(withTitle: "Läuft weiter")
        alert.addButton(withTitle: "Jetzt stoppen")
        alert.addButton(withTitle: "Stoppen um …")
        alert.buttons.last?.toolTip = "Stoppt den Timer und zeigt „Heute“, um das Ende zu korrigieren."

        let entryId = running.entry.id
        let respond: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            self.isAlertShown = false
            switch response {
            case .alertFirstButtonReturn: self.handle(.keepRunning, entryId: entryId)
            case .alertSecondButtonReturn: self.handle(.stopNow, entryId: entryId)
            case .alertThirdButtonReturn: self.handle(.stopAt, entryId: entryId)
            default: self.handle(.keepRunning, entryId: entryId)
            }
        }

        isAlertShown = true
        if let window = MenuBarController.mainWindow(), window.isVisible, window.attachedSheet == nil {
            alert.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated { respond(response) }
            }
        } else {
            NSApp.activate()
            respond(alert.runModal())
        }
    }

    /// „Gestartet 09:12, seit 8:05.“ – liegt der Start nicht heute, mit Datum.
    private static func detail(for running: RunningState, now: Date) -> String {
        let start = running.entry.startedAt
        let calendar = Calendar.current
        let day: String
        if calendar.isDate(start, inSameDayAs: now) {
            day = ""
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                  calendar.isDate(start, inSameDayAs: yesterday) {
            day = "gestern "
        } else {
            day = "am \(start.formatted(.dateTime.day(.twoDigits).month(.twoDigits).locale(Locale(identifier: "de_DE")))). "
        }
        let duration = DurationFormat.hourMinute(running.entry.duration(at: now))
        return "Gestartet \(day)\(ClockFormat.time(start)), seit \(duration)."
    }

    // MARK: Mitteilung

    private enum ID {
        static let request = "dev.eremiya.takt.forgotten-timer"
        static let category = NotificationCategories.ForgottenTimer.category
        static let keepRunning = NotificationCategories.ForgottenTimer.keepRunning
        static let stopNow = NotificationCategories.ForgottenTimer.stopNow
        static let stopAt = NotificationCategories.ForgottenTimer.stopAt
        static let entryKey = "entryId"
    }

    private func postNotification(for running: RunningState, now: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Läuft ‚\(running.project.name)‘ wirklich noch?"
        content.body = Self.detail(for: running, now: now)
        content.sound = .default
        content.categoryIdentifier = ID.category
        content.userInfo = [ID.entryKey: running.entry.id.uuidString]

        // Ohne Auslöser = sofort zustellen; gleiche Kennung ersetzt eine ältere Nachfrage.
        let request = UNNotificationRequest(identifier: ID.request, content: content, trigger: nil)
        let center = center
        Task {
            let status = await center.notificationSettings().authorizationStatus
            if status == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            do {
                try await center.add(request)
                Self.logger.info("Nachfrage vergessener Timer zugestellt.")
            } catch {
                Self.logger.error("Nachfrage nicht zugestellt: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func removeNotification() {
        center.removeDeliveredNotifications(withIdentifiers: [ID.request])
        center.removePendingNotificationRequests(withIdentifiers: [ID.request])
    }

    /// Ob die Mitteilung zu dieser Nachfrage gehört (für die Weiterleitung im Delegate).
    nonisolated static func handles(_ notification: UNNotification) -> Bool {
        notification.request.identifier == ID.request
    }

    /// Vom Notification-Delegate (`BreakReminder`) weitergereicht.
    nonisolated static func handleNotificationResponse(_ response: UNNotificationResponse) {
        let action = response.actionIdentifier
        guard let text = response.notification.request.content.userInfo[ID.entryKey] as? String,
              let entryId = UUID(uuidString: text)
        else { return }
        Task { @MainActor in
            guard let guardian = current else { return }
            switch action {
            case ID.keepRunning: guardian.handle(.keepRunning, entryId: entryId)
            case ID.stopNow: guardian.handle(.stopNow, entryId: entryId)
            case ID.stopAt: guardian.handle(.stopAt, entryId: entryId)
            case UNNotificationDefaultActionIdentifier:
                // Klick auf die Mitteilung: App nach vorn und dort ausführlich nachfragen.
                guard let running = guardian.store.running, running.entry.id == entryId,
                      !guardian.isAlertShown else { return }
                NSApp.activate()
                guardian.showAlert(for: running, now: .now)
            default:
                break  // Verworfen: bleibt „gefragt“, keine erneute Nachfrage für diesen Eintrag.
            }
        }
    }
}
