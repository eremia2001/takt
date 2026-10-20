import AppKit
import Foundation
import Observation
import os
import TaktCore
import UserNotifications

/// Pomodoro-Modus: Arbeit (`pomodoroWorkMinutes`) → kurze Pause → … nach
/// `pomodoroCyclesBeforeLongBreak` Einheiten eine lange Pause.
///
/// - Eine Arbeitseinheit beginnt mit dem Timer-Start (Übergang „nichts läuft“ → „läuft“) und endet
///   mit ihrem Ablauf; ein Stopp davor bricht sie ab (die Einheit zählt nicht). Projektwechsel
///   setzen sie nicht zurück.
/// - Ende der Arbeit: Mitteilung „Pomodoro: Pause (10 Min)“; mit `pomodoroAutoStopTimer` wird der
///   Timer gestoppt (die Musik pausiert dann über den Store von selbst).
/// - Ende der Pause: Mitteilung „Pause vorbei – weiter mit …?“ mit Aktion „Weiter“ und eine
///   Einblendung wie beim Kurzbefehl. Ein Timer-Start während der Pause beendet sie vorzeitig.
/// - Ersetzt die normale Pausenerinnerung (`BreakReminder` prüft `pomodoroEnabled`).
/// - Zustand nur im Speicher; nach einem Neustart beginnt der Zyklus bei 1.
@MainActor
@Observable
final class PomodoroController {
    enum Phase: Equatable {
        case work, shortBreak, longBreak

        var isBreak: Bool { self != .work }
    }

    /// Aktuelle Phase; `nil` = bereit (wartet auf den nächsten Timer-Start) oder ausgeschaltet.
    private(set) var phase: Phase?
    /// Beginn der aktuellen Phase.
    private(set) var phaseStart: Date?
    /// Laufende bzw. zuletzt beendete Einheit, ab 1.
    private(set) var cycle = 1
    /// Takt für Restzeit-Anzeigen: jeweils zur vollen Restminute der Phase.
    private(set) var tick = Date.now

    @ObservationIgnored private let store: TaktStore
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let breakReminder: BreakReminder
    @ObservationIgnored private let menuBar: MenuBarController
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// Zuletzt gesehener Zustand, um Übergänge zu erkennen.
    @ObservationIgnored private var lastRunningId: UUID?
    @ObservationIgnored private var lastEnabled: Bool?
    /// Projekt der letzten Arbeitseinheit (Rückfall für „Weiter mit …“).
    @ObservationIgnored private var lastWorkProject: Project?

    /// Für die Weiterleitung aus dem Notification-Delegate.
    private static weak var current: PomodoroController?
    private static let logger = Logger(subsystem: "dev.eremiya.takt", category: "focus")

    init(store: TaktStore, settings: AppSettings, breakReminder: BreakReminder, menuBar: MenuBarController) {
        self.store = store
        self.settings = settings
        self.breakReminder = breakReminder
        self.menuBar = menuBar
        Self.current = self

        // Nach dem Aufwachen Restzeit sofort neu rechnen (ggf. ist die Phase inzwischen vorbei).
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tick = .now
                self.restartLoop()
            }
        })

        observeContinuously { [weak self] in
            guard let self else { return }
            // Nur lesen (und damit beobachten); die Auswertung läuft außerhalb der Beobachtung,
            // damit eigene Zustandsänderungen keinen erneuten Durchlauf auslösen.
            let running = self.store.running
            let enabled = self.settings.pomodoroEnabled
            _ = self.settings.pomodoroWorkMinutes
            _ = self.settings.pomodoroBreakMinutes
            _ = self.settings.pomodoroLongBreakMinutes
            _ = self.settings.pomodoroCyclesBeforeLongBreak
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.sync(running: running, enabled: enabled) }
            }
        }
    }

    // MARK: Anzeige

    /// Zustand für Menüleiste und Popover; `nil`, wenn keine Phase läuft.
    struct Status: Equatable {
        let phase: Phase
        let cycle: Int
        let cycles: Int
        let remaining: TimeInterval
    }

    func status(at date: Date) -> Status? {
        guard settings.pomodoroEnabled, let phase, let end = phaseEnd else { return nil }
        let cycles = settings.pomodoroCyclesBeforeLongBreak
        return Status(phase: phase, cycle: min(cycle, cycles), cycles: cycles,
                      remaining: max(0, end.timeIntervalSince(date)))
    }

    /// Zusatz für die Menüleiste: „🍅 23:00“ in der Arbeit, „Pause 07:00“ in der Pause.
    func menuBarSuffix(at date: Date) -> String? {
        guard let status = status(at: date) else { return nil }
        let clock = Self.clock(status.remaining)
        return status.phase.isBreak ? "Pause \(clock)" : "🍅 \(clock)"
    }

    /// Zeile im Popover: „Pomodoro 2/4 · Arbeit · noch 23 min“.
    func panelLine(at date: Date) -> String? {
        guard let status = status(at: date) else { return nil }
        let name = switch status.phase {
        case .work: "Arbeit"
        case .shortBreak: "Pause"
        case .longBreak: "Lange Pause"
        }
        return "Pomodoro \(status.cycle)/\(status.cycles) · \(name) · noch \(Self.remainingMinutes(status.remaining)) min"
    }

    /// Restzeit in angefangenen Minuten (wie ein Küchenwecker: „noch 1 min“ bis zum Ende).
    static func remainingMinutes(_ remaining: TimeInterval) -> Int {
        max(0, Int((remaining / 60).rounded(.up)))
    }

    /// Restzeit als „mm:00“ (bzw. „h:mm:00“ ab einer Stunde); minütlich aktualisiert.
    static func clock(_ remaining: TimeInterval) -> String {
        let minutes = remainingMinutes(remaining)
        if minutes >= 60 { return String(format: "%d:%02d:00", minutes / 60, minutes % 60) }
        return String(format: "%02d:00", minutes)
    }

    // MARK: Aktionen

    /// „Phase überspringen“: Arbeit endet sofort (wie regulär, inkl. Stopp), eine Pause endet ohne Mitteilung.
    func skipPhase() {
        guard settings.pomodoroEnabled, let phase else { return }
        Self.logger.info("Pomodoro-Phase übersprungen.")
        if phase == .work {
            workDidEnd(at: .now)
        } else {
            breakDidEnd(announce: false)
        }
    }

    // MARK: Übergänge

    private func sync(running: RunningState?, enabled: Bool) {
        let wasRunning = lastRunningId != nil
        lastRunningId = running?.entry.id

        if enabled != lastEnabled {
            let wasEnabled = lastEnabled == true
            lastEnabled = enabled
            // Pausenerinnerung neu planen bzw. aufheben.
            breakReminder.settingsDidChange()
            if enabled {
                Self.logger.info("Pomodoro eingeschaltet.")
                if let running, phase == nil {
                    // Beim App-Start oder Einschalten mit laufendem Timer: Einheit beginnt jetzt
                    // (bzw. mit dem Eintrag, wenn der noch innerhalb einer Einheit liegt).
                    beginWork(start: startDate(for: running.entry, allowedBack: workDuration))
                }
            } else if wasEnabled {
                reset()
            }
            return
        }
        guard enabled else { return }

        if !wasRunning, let running {
            timerDidStart(running)
        } else if wasRunning, running == nil {
            timerDidStop()
        }
        // Dauer in den Einstellungen geändert? Ende neu planen.
        restartLoop()
    }

    private func timerDidStart(_ running: RunningState) {
        if let phase, phase.isBreak {
            // Start während der Pause: Pause endet vorzeitig, nächste Einheit beginnt.
            Self.logger.info("Timer-Start in der Pause – nächste Einheit beginnt.")
            advanceAfterBreak(wasLong: phase == .longBreak)
            NotificationCategories.remove(identifier: ID.breakOver, center: .current())
        }
        // Starts aus dem Widget o. ä. liegen evtl. Sekunden zurück; rückwirkende Starts nicht.
        beginWork(start: startDate(for: running.entry, allowedBack: 5 * 60))
    }

    private func timerDidStop() {
        guard phase == .work else { return }
        // Stopp vor Ablauf: Einheit abgebrochen, zählt nicht.
        Self.logger.info("Pomodoro-Einheit \(self.cycle) abgebrochen (Timer gestoppt).")
        phase = nil
        phaseStart = nil
        restartLoop()
    }

    private func beginWork(start: Date) {
        phase = .work
        phaseStart = start
        if let project = store.running?.project { lastWorkProject = project }
        tick = .now
        restartLoop()
        Self.logger.info("Pomodoro-Einheit \(self.cycle) beginnt um \(ClockFormat.time(start), privacy: .public).")
    }

    /// Arbeitseinheit vorbei: Pause beginnt, Mitteilung, ggf. Timer stoppen.
    private func workDidEnd(at end: Date) {
        let cycles = settings.pomodoroCyclesBeforeLongBreak
        let finished = min(cycle, cycles)
        let isLong = cycle >= cycles
        let minutes = isLong ? settings.pomodoroLongBreakMinutes : settings.pomodoroBreakMinutes
        if let project = store.running?.project { lastWorkProject = project }

        phase = isLong ? .longBreak : .shortBreak
        phaseStart = .now
        tick = .now

        let autoStop = settings.pomodoroAutoStopTimer && store.running != nil
        let content = UNMutableNotificationContent()
        content.title = "Pomodoro: \(isLong ? "lange Pause" : "Pause") (\(minutes) Min)"
        content.body = autoStop
            ? "Einheit \(finished) von \(cycles) geschafft – der Timer ist gestoppt."
            : "Einheit \(finished) von \(cycles) geschafft. Der Timer läuft weiter."
        content.sound = .default
        NotificationCategories.deliverNow(identifier: ID.breakStart, content: content)
        Self.logger.info("Pomodoro-Einheit \(finished) beendet – \(isLong ? "lange " : "", privacy: .public)Pause \(minutes) Min.")

        if autoStop {
            // Kam das Ende verspätet (z. B. nach dem Ruhezustand), zum eigentlichen Ende stoppen.
            if Date.now.timeIntervalSince(end) > 60 {
                store.stop(at: end, nextStep: nil)
            } else {
                store.stop(nextStep: nil)
            }
        }
        restartLoop()
    }

    /// Pause vorbei. Läuft der Timer noch (ohne automatischen Stopp), beginnt die nächste Einheit
    /// sofort; sonst „Weiter mit …?“.
    private func breakDidEnd(announce: Bool) {
        guard let phase, phase.isBreak else { return }
        advanceAfterBreak(wasLong: phase == .longBreak)
        NotificationCategories.remove(identifier: ID.breakStart, center: .current())

        if store.running != nil {
            beginWork(start: .now)
            guard announce else { return }
            let cycles = settings.pomodoroCyclesBeforeLongBreak
            let content = UNMutableNotificationContent()
            content.title = "Pause vorbei"
            content.body = "Einheit \(min(cycle, cycles)) von \(cycles) läuft."
            content.sound = .default
            NotificationCategories.deliverNow(identifier: ID.breakOver, content: content)
            menuBar.showOverlay(HotKeyOverlayMessage(kind: .pomodoro, text: "Pause vorbei · Einheit \(min(cycle, cycles))"),
                                visibleFor: Self.overlayDuration)
            return
        }

        self.phase = nil
        phaseStart = nil
        restartLoop()
        guard announce else { return }

        let project = store.lastUsedProject ?? lastWorkProject
        let content = UNMutableNotificationContent()
        if let project {
            content.title = "Pause vorbei – weiter mit \(project.name)?"
            content.body = "„Weiter“ startet den Timer für die nächste Einheit."
            content.categoryIdentifier = NotificationCategories.PomodoroBreakOver.category
            content.userInfo = [ID.projectKey: project.id.uuidString]
        } else {
            content.title = "Pause vorbei"
            content.body = "Starte einen Timer für die nächste Einheit."
        }
        content.sound = .default
        NotificationCategories.deliverNow(identifier: ID.breakOver, content: content)
        menuBar.showOverlay(
            HotKeyOverlayMessage(
                kind: .pomodoro,
                text: project.map { "Pause vorbei – weiter mit \($0.name)?" } ?? "Pause vorbei",
                colorHex: project?.colorHex
            ),
            visibleFor: Self.overlayDuration
        )
        Self.logger.info("Pomodoro-Pause vorbei.")
    }

    private func advanceAfterBreak(wasLong: Bool) {
        cycle = wasLong ? 1 : min(cycle, settings.pomodoroCyclesBeforeLongBreak) % settings.pomodoroCyclesBeforeLongBreak + 1
    }

    /// Ausgeschaltet: alles zurück auf Anfang.
    private func reset() {
        phase = nil
        phaseStart = nil
        cycle = 1
        restartLoop()
        NotificationCategories.remove(identifier: ID.breakStart, center: .current())
        NotificationCategories.remove(identifier: ID.breakOver, center: .current())
        Self.logger.info("Pomodoro ausgeschaltet.")
    }

    // MARK: Zeitplan

    private var workDuration: TimeInterval { TimeInterval(settings.pomodoroWorkMinutes) * 60 }

    private func duration(of phase: Phase) -> TimeInterval {
        switch phase {
        case .work: workDuration
        case .shortBreak: TimeInterval(settings.pomodoroBreakMinutes) * 60
        case .longBreak: TimeInterval(settings.pomodoroLongBreakMinutes) * 60
        }
    }

    /// Ende der aktuellen Phase (folgt geänderten Einstellungen sofort).
    var phaseEnd: Date? {
        guard let phase, let phaseStart else { return nil }
        return phaseStart.addingTimeInterval(duration(of: phase))
    }

    /// Beginn des Eintrags, wenn er höchstens `allowedBack` zurückliegt, sonst jetzt.
    private func startDate(for entry: TimeEntry, allowedBack: TimeInterval) -> Date {
        let now = Date.now
        let back = now.timeIntervalSince(entry.startedAt)
        return back >= 0 && back < allowedBack ? entry.startedAt : now
    }

    /// Wartet jeweils bis zur nächsten vollen Restminute (für die Anzeige) bzw. bis zum Phasenende.
    private func restartLoop() {
        loopTask?.cancel()
        loopTask = nil
        guard settings.pomodoroEnabled, phaseEnd != nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let end = self?.phaseEnd else { return }
                let remaining = end.timeIntervalSinceNow
                if remaining <= 0.5 {
                    self?.phaseDidEnd()
                    return
                }
                let step = remaining.truncatingRemainder(dividingBy: 60)
                try? await Task.sleep(for: .seconds(min(step, remaining) + 0.05))
                guard !Task.isCancelled else { return }
                self?.tick = .now
            }
        }
    }

    private func phaseDidEnd() {
        guard let phase else { return }
        if phase == .work {
            workDidEnd(at: phaseEnd ?? .now)
        } else {
            breakDidEnd(announce: true)
        }
    }

    // MARK: Mitteilungen

    private static let overlayDuration: Duration = .seconds(2)

    private enum ID {
        static let breakStart = "dev.eremiya.takt.pomodoro-break"
        static let breakOver = "dev.eremiya.takt.pomodoro-break-over"
        static let projectKey = "projectId"
    }

    /// Ob die Mitteilung zum Pomodoro gehört (für die Weiterleitung im Delegate).
    nonisolated static func handles(_ notification: UNNotification) -> Bool {
        let id = notification.request.identifier
        return id == ID.breakStart || id == ID.breakOver
    }

    /// Vom Notification-Delegate (`BreakReminder`) weitergereicht: „Weiter“ startet das Projekt.
    nonisolated static func handleNotificationResponse(_ response: UNNotificationResponse) {
        guard response.actionIdentifier == NotificationCategories.PomodoroBreakOver.resume,
              let text = response.notification.request.content.userInfo[ID.projectKey] as? String,
              let projectId = UUID(uuidString: text)
        else { return }
        Task { @MainActor in
            guard let controller = current else { return }
            // Läuft inzwischen schon etwas, nichts umschalten.
            guard controller.store.running == nil else { return }
            controller.store.start(projectId: projectId)
            Self.logger.info("Pomodoro: weiter nach der Pause.")
        }
    }
}
