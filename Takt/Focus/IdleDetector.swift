import AppKit
import CoreGraphics
import Foundation
import os
import TaktCore
import UserNotifications

/// Erkennt Leerlauf bei laufendem Timer und fragt nach der Rückkehr, was mit der Zeit passieren soll.
///
/// - Alle 30 s: Sekunden seit der letzten Eingabe (Tastatur, Maus, Trackpad) über
///   `CGEventSource.secondsSinceLastEventType`. Ab `idleMinutes` gilt der Zeitraum als Leerlauf;
///   sein Beginn ist „jetzt − Leerlauf“.
/// - Ruhezustand und Bildschirmsperre zählen ebenfalls als Leerlauf (Beginn = letzte Eingabe davor).
/// - Während eines Leerlaufs wird alle 2 s geprüft; kommt wieder eine Eingabe (< 5 s her) und läuft
///   derselbe Timer noch, folgt die Nachfrage: App aktiv → `NSAlert`, sonst zuerst eine Mitteilung
///   („Abziehen“ / „Behalten“, Klick darauf zeigt den Alert). Antworten auf die Mitteilung kommen
///   über das Delegate von `BreakReminder`.
@MainActor
final class IdleDetector {
    private let store: TaktStore
    private let settings: AppSettings
    private let center = UNUserNotificationCenter.current()

    /// Laufender Leerlauf, der noch auf die Rückkehr wartet.
    private struct Episode {
        let start: Date
        let entryId: UUID
    }

    /// Erkannter, abgeschlossener Leerlauf, zu dem eine Antwort aussteht.
    struct Decision {
        let entryId: UUID
        let projectName: String
        let idleStart: Date
        let idleEnd: Date

        var duration: TimeInterval { idleEnd.timeIntervalSince(idleStart) }
    }

    private enum Answer {
        case subtract, keep, stopAtIdle
    }

    private var episode: Episode?
    /// Während Ruhezustand bzw. Sperre keine Rückkehr werten (Eingaben am Sperrbildschirm zählen nicht).
    private var isAsleep = false
    private var isLocked = false
    private var isAlertShown = false

    private var checkTimer: Timer?
    private var returnTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    /// Normale Prüfung.
    private static let checkInterval: TimeInterval = 30
    /// Prüfung während eines Leerlaufs, damit die Nachfrage kurz nach der Rückkehr kommt.
    private static let returnCheckInterval: TimeInterval = 2
    /// Eingabe jünger als das gilt als Rückkehr.
    private static let returnThreshold: TimeInterval = 5
    /// Kürzere Lücken lohnen das Aufteilen beim „Abziehen“ nicht.
    private static let minimumGap: TimeInterval = 2 * 60

    /// Für die Weiterleitung aus dem Notification-Delegate.
    private static weak var current: IdleDetector?
    private static let logger = Logger(subsystem: "dev.eremiya.takt", category: "focus")

    init(store: TaktStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        Self.current = self

        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        checkTimer = timer

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.suspend(reason: "Ruhezustand") { $0.isAsleep = true } }
        })
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resume { $0.isAsleep = false } }
        })

        let distributed = DistributedNotificationCenter.default()
        distributedObservers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.suspend(reason: "Bildschirmsperre") { $0.isLocked = true } }
        })
        distributedObservers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resume { $0.isLocked = false } }
        })
    }

    // MARK: Messung

    /// Sekunden seit der letzten Eingabe (beliebiger Typ) in der aktuellen Sitzung.
    nonisolated static func secondsSinceLastInput() -> TimeInterval {
        // `kCGAnyInputEventType` (~0) ist in Swift kein eigener Fall von `CGEventType`.
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    // MARK: Prüfung

    /// Prüft Beginn bzw. Ende eines Leerlaufs.
    func check(now: Date = .now) {
        guard settings.idleDetectionEnabled, let running = store.running else {
            endEpisode()
            return
        }
        let idle = Self.secondsSinceLastInput()

        if let episode {
            // Anderer Eintrag (gestoppt und neu gestartet, z. B. vom Pomodoro)? Dann ist die Frage hinfällig.
            guard episode.entryId == running.entry.id else {
                endEpisode()
                return
            }
            guard !isAsleep, !isLocked, idle < Self.returnThreshold else { return }
            endEpisode()
            didReturn(from: episode, idleEnd: now.addingTimeInterval(-idle), running: running)
            return
        }

        guard idle >= limit else { return }
        beginEpisode(start: now.addingTimeInterval(-idle), running: running)
    }

    private var limit: TimeInterval { TimeInterval(settings.idleMinutes) * 60 }

    private func beginEpisode(start: Date, running: RunningState) {
        episode = Episode(start: start, entryId: running.entry.id)
        Self.logger.info("Leerlauf seit \(ClockFormat.time(start), privacy: .public) erkannt.")
        guard returnTimer == nil else { return }
        let timer = Timer(timeInterval: Self.returnCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        returnTimer = timer
    }

    private func endEpisode() {
        episode = nil
        returnTimer?.invalidate()
        returnTimer = nil
    }

    /// Ruhezustand oder Sperre beginnt: zählt als Leerlauf ab der letzten Eingabe.
    private func suspend(reason: String, _ mark: (IdleDetector) -> Void) {
        mark(self)
        guard settings.idleDetectionEnabled, let running = store.running, episode == nil else { return }
        Self.logger.info("\(reason, privacy: .public): Leerlauf beginnt.")
        beginEpisode(start: Date.now.addingTimeInterval(-Self.secondsSinceLastInput()), running: running)
    }

    /// Aufwachen bzw. Entsperren: Rückkehr wertet die nächste Prüfung (sobald Eingaben kommen).
    private func resume(_ mark: (IdleDetector) -> Void) {
        mark(self)
        check()
    }

    /// Nutzer ist zurück. Nur nachfragen, wenn der Leerlauf (innerhalb des Eintrags) lang genug war.
    private func didReturn(from episode: Episode, idleEnd: Date, running: RunningState) {
        let start = max(episode.start, running.entry.startedAt)
        let decision = Decision(
            entryId: running.entry.id,
            projectName: running.project.name,
            idleStart: start,
            idleEnd: max(idleEnd, start)
        )
        guard decision.duration >= limit else {
            Self.logger.info("Zurück nach \(Int(decision.duration / 60)) Min – unter der Grenze, keine Nachfrage.")
            return
        }
        Self.logger.info("Zurück nach \(Int(decision.duration / 60)) Min Leerlauf.")
        if NSApp.isActive {
            showAlert(for: decision)
        } else {
            postNotification(for: decision)
        }
    }

    // MARK: Antworten

    private func handle(_ answer: Answer, decision: Decision) {
        NotificationCategories.remove(identifier: ID.request, center: center)
        // Inzwischen anderswo gestoppt oder gewechselt? Dann nichts tun.
        guard let running = store.running, running.entry.id == decision.entryId else {
            Self.logger.info("Leerlauf-Antwort verworfen: Timer läuft nicht mehr.")
            return
        }
        let coversWholeEntry = decision.idleStart <= running.entry.startedAt.addingTimeInterval(1)

        switch answer {
        case .keep:
            Self.logger.info("Leerlauf behalten.")

        case .subtract:
            guard decision.duration >= Self.minimumGap else {
                Self.logger.info("Leerlauf unter 2 Min – nichts abgezogen.")
                return
            }
            if coversWholeEntry {
                // Leerlauf ab Beginn: kein leerer Eintrag, sondern den Beginn verschieben.
                var entry = running.entry
                entry.startedAt = min(decision.idleEnd, .now)
                store.updateEntry(entry)
            } else {
                // Eintrag endet zum Beginn des Leerlaufs; derselbe Timer (Projekt, Tag,
                // Abrechenbarkeit) läuft ab dem Ende des Leerlaufs weiter → zwei Einträge mit Lücke.
                let projectId = running.project.id
                let tag = running.entry.tag
                let billable = running.entry.isBillable
                guard store.stop(at: decision.idleStart, nextStep: nil) else { return }
                guard store.start(projectId: projectId, tag: tag), var entry = store.running?.entry else { return }
                let resumedAt = min(decision.idleEnd, .now)
                if entry.startedAt > resumedAt || entry.isBillable != billable {
                    entry.startedAt = min(entry.startedAt, resumedAt)
                    entry.isBillable = billable
                    store.updateEntry(entry)
                }
            }
            Self.logger.info("Leerlauf abgezogen (\(Int(decision.duration / 60)) Min).")

        case .stopAtIdle:
            if coversWholeEntry {
                store.discardRunning()
            } else {
                store.stop(at: decision.idleStart, nextStep: nil)
            }
            Self.logger.info("Timer zum Beginn des Leerlaufs gestoppt.")
        }
    }

    // MARK: Alert

    private func showAlert(for decision: Decision) {
        guard !isAlertShown else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Du warst \(Self.minutesText(decision.duration)) inaktiv (seit \(ClockFormat.time(decision.idleStart)))."
        alert.informativeText = "Was soll mit der Zeit passieren? „Abziehen“ beendet ‚\(decision.projectName)‘ "
            + "um \(ClockFormat.time(decision.idleStart)) und setzt den Timer ab \(ClockFormat.time(decision.idleEnd)) fort."
        alert.addButton(withTitle: "Abziehen")
        alert.addButton(withTitle: "Behalten")
        alert.addButton(withTitle: "Bei Leerlauf stoppen")
        // Esc = Behalten.
        alert.buttons[1].keyEquivalent = "\u{1b}"

        let respond: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            self.isAlertShown = false
            switch response {
            case .alertFirstButtonReturn: self.handle(.subtract, decision: decision)
            case .alertThirdButtonReturn: self.handle(.stopAtIdle, decision: decision)
            default: self.handle(.keep, decision: decision)
            }
        }

        isAlertShown = true
        NSApp.activate()
        if let window = MenuBarController.mainWindow(), window.isVisible, window.attachedSheet == nil {
            alert.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated { respond(response) }
            }
        } else {
            respond(alert.runModal())
        }
    }

    /// „1 Minute“, „23 Minuten“, „1:05 Stunden“.
    static func minutesText(_ duration: TimeInterval) -> String {
        let minutes = max(1, Int((duration / 60).rounded()))
        if minutes >= 60 { return "\(DurationFormat.hourMinute(TimeInterval(minutes * 60))) Stunden" }
        return minutes == 1 ? "1 Minute" : "\(minutes) Minuten"
    }

    // MARK: Mitteilung

    private enum ID {
        static let request = "dev.eremiya.takt.idle"
        static let entryKey = "entryId"
        static let projectKey = "projectName"
        static let startKey = "idleStart"
        static let endKey = "idleEnd"
    }

    private func postNotification(for decision: Decision) {
        let minutes = max(1, Int((decision.duration / 60).rounded()))
        let content = UNMutableNotificationContent()
        content.title = "\(minutes) Min Leerlauf erkannt – klicken zum Entscheiden"
        content.body = "Seit \(ClockFormat.time(decision.idleStart)) lief ‚\(decision.projectName)‘ weiter. Abziehen oder behalten?"
        content.sound = .default
        content.categoryIdentifier = NotificationCategories.Idle.category
        content.userInfo = [
            ID.entryKey: decision.entryId.uuidString,
            ID.projectKey: decision.projectName,
            ID.startKey: decision.idleStart.timeIntervalSince1970,
            ID.endKey: decision.idleEnd.timeIntervalSince1970,
        ]
        NotificationCategories.deliverNow(identifier: ID.request, content: content, center: center)
        Self.logger.info("Leerlauf-Mitteilung zugestellt.")
    }

    /// Ob die Mitteilung zum Leerlauf gehört (für die Weiterleitung im Delegate).
    nonisolated static func handles(_ notification: UNNotification) -> Bool {
        notification.request.identifier == ID.request
    }

    /// Vom Notification-Delegate (`BreakReminder`) weitergereicht.
    nonisolated static func handleNotificationResponse(_ response: UNNotificationResponse) {
        let info = response.notification.request.content.userInfo
        guard let entryText = info[ID.entryKey] as? String, let entryId = UUID(uuidString: entryText),
              let start = info[ID.startKey] as? Double, let end = info[ID.endKey] as? Double
        else { return }
        let decision = Decision(
            entryId: entryId,
            projectName: info[ID.projectKey] as? String ?? "Timer",
            idleStart: Date(timeIntervalSince1970: start),
            idleEnd: Date(timeIntervalSince1970: end)
        )
        let action = response.actionIdentifier
        Task { @MainActor in
            guard let detector = current else { return }
            switch action {
            case NotificationCategories.Idle.subtract: detector.handle(.subtract, decision: decision)
            case NotificationCategories.Idle.keep: detector.handle(.keep, decision: decision)
            case UNNotificationDefaultActionIdentifier:
                // Klick auf die Mitteilung: App nach vorn und dort mit allen drei Möglichkeiten fragen.
                guard detector.store.running?.entry.id == entryId else { return }
                detector.showAlert(for: decision)
            default:
                break  // Verworfen = Behalten.
            }
        }
    }
}
