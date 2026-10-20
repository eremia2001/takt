import Foundation
import TaktCore
import WidgetKit

/// Ein Timeline-Eintrag: Momentaufnahme aus der Datenbank plus Anzeigezeitpunkt.
/// Alle Zeitwerte werden aus `date` berechnet – nie aus `Date.now`.
struct TaktEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// Zeitpunkt, zu dem `snapshot` gelesen wurde (bezieht sich auf dessen Kalendertag).
    let snapshotDate: Date
    /// Darstellung (aus der Widget-Konfiguration aufgelöst); pro Timeline einmal bestimmt,
    /// damit alle Einträge gleich aussehen.
    let style: WidgetStyle

    init(date: Date, snapshot: WidgetSnapshot, snapshotDate: Date? = nil, style: WidgetStyle = .plain) {
        self.date = date
        self.snapshot = snapshot
        self.snapshotDate = snapshotDate ?? date
        self.style = style
    }

    // MARK: Abgeleitete Werte (alle bezogen auf `date`)

    var running: RunningState? { snapshot.running }

    /// Dauer des laufenden Eintrags zum Zeitpunkt des Timeline-Eintrags.
    var runningDuration: TimeInterval {
        snapshot.running?.entry.duration(at: date) ?? 0
    }

    /// Tagessumme zum Zeitpunkt des Timeline-Eintrags: abgeschlossene Einträge plus der heutige
    /// Anteil des laufenden. Liegt `date` schon im nächsten Tag (Mitternacht innerhalb der
    /// Timeline), zählen die abgeschlossenen Einträge des Vortags nicht mehr.
    /// Im Ein-Projekt-Widget nur dieses Projekt (so liefert es die Momentaufnahme).
    var todayTotal: TimeInterval {
        let calendar = Calendar.current
        let completed = isSnapshotDay ? snapshot.todayCompleted : 0
        guard let running = snapshot.running else { return completed }
        let start = max(running.entry.startedAt, calendar.startOfDay(for: date))
        return completed + max(0, date.timeIntervalSince(start))
    }

    /// `date` liegt noch im Kalendertag der Momentaufnahme.
    var isSnapshotDay: Bool {
        Calendar.current.isDate(snapshotDate, inSameDayAs: date)
    }

    /// Ein-Projekt-Widget.
    var isFixed: Bool { snapshot.fixedProjectID != nil }

    /// Fortschritt bis zur Pausenerinnerung (0 … 1, gedeckelt); `nil` ohne Erinnerung oder Timer.
    var breakFraction: Double? {
        guard snapshot.running != nil, let minutes = snapshot.breakReminderMinutes, minutes > 0 else { return nil }
        return min(1, runningDuration / (Double(minutes) * 60))
    }

    /// Laufende Pomodoro-Phase zu `date`: Modus an, Phase nicht `.idle`, Ende noch nicht erreicht.
    /// `nil` sonst – dann gilt wieder der Pausenstrich bzw. nichts.
    var pomodoro: PomodoroDisplay? {
        guard let state = snapshot.pomodoro, state.enabled, state.isActive(at: date) else { return nil }
        return PomodoroDisplay(state: state, date: date)
    }

    /// Pomodoro-Pause ohne laufenden Timer (Pause-Zustand: „Pause · noch 7 min“).
    var pomodoroBreak: PomodoroDisplay? {
        guard let pomodoro, pomodoro.isBreak else { return nil }
        return pomodoro
    }

    /// Budget mit live hochgerechnetem Verbrauch.
    /// Läuft ein Timer, ist es das Budget des laufenden Projekts, im Ein-Projekt-Widget das des
    /// festen Projekts (auch ohne laufenden Timer).
    var budget: BudgetDisplay? {
        guard let info = snapshot.runningBudget else { return nil }
        let since = snapshot.running?.entry.startedAt
        return BudgetDisplay(
            used: info.used(at: date, runningSince: since),
            budget: info.budget,
            fraction: info.fraction(at: date, runningSince: since)
        )
    }

    /// Geplanter Block. Im Lauf-Zustand nicht, wenn er zum laufenden Projekt gehört und schon
    /// fällig ist – dann ist er praktisch erledigt.
    var plannedBlock: WidgetSnapshot.PlannedBlockInfo? {
        guard let block = snapshot.plannedBlock else { return nil }
        if let running = snapshot.running, running.project.id == block.project.id, block.isDue(at: date) {
            return nil
        }
        return block
    }

    /// Einträge für die Tagesleiste; im Ein-Projekt-Widget nur die des festen Projekts.
    /// Nach Mitternacht (innerhalb der Timeline) nur noch der laufende Eintrag ab 0:00.
    var dayEntries: [WidgetSnapshot.TodayEntry] {
        var entries = snapshot.todayEntries
        if let fixed = snapshot.fixedProjectID {
            entries = entries.filter { $0.projectId == fixed }
        }
        guard isSnapshotDay else {
            let midnight = Calendar.current.startOfDay(for: date)
            return entries.filter(\.isRunning).map {
                WidgetSnapshot.TodayEntry(
                    projectId: $0.projectId, colorHex: $0.colorHex, startedAt: max($0.startedAt, midnight), endedAt: nil
                )
            }
        }
        return entries
    }

    /// Heutige Zeit eines Projekts (Projektliste im großen Widget), laufender Eintrag bis `date`.
    func todayTime(for projectID: UUID) -> TimeInterval {
        dayEntries
            .filter { $0.projectId == projectID }
            .reduce(0) { $0 + max(0, ($1.endedAt ?? date).timeIntervalSince($1.startedAt)) }
    }
}

/// Budgetanzeige: Verbrauch, Budget, Anteil (> 1 = überzogen).
struct BudgetDisplay: Hashable {
    let used: TimeInterval
    let budget: TimeInterval
    let fraction: Double

    /// „12:30 / 40 h“ bzw. „3:15 / 12,5 h“.
    var label: String {
        let hours = (budget / 3600).formatted(
            .number.precision(.fractionLength(0...1)).locale(Locale(identifier: "de_DE"))
        )
        return "\(DurationFormat.hourMinute(used)) / \(hours) h"
    }
}

/// Pomodoro-Phase für die Anzeige, bezogen auf einen Zeitpunkt.
///
/// Beginn der Phase ist `PomodoroState.updatedAt` – der `PomodoroController` schreibt dort den
/// Phasenbeginn hinein (siehe docs/spec-widget-pomodoro-budget.md); daraus und aus `phaseEndsAt`
/// ergibt sich der verstrichene Anteil.
struct PomodoroDisplay: Hashable {
    let phase: PomodoroState.Phase
    let cycle: Int
    let cycles: Int
    /// Restzeit, nie negativ.
    let remaining: TimeInterval
    /// Verstrichener Anteil der Phase (0 … 1).
    let fraction: Double

    init(state: PomodoroState, date: Date) {
        phase = state.phase
        cycles = max(1, state.cyclesBeforeLongBreak)
        cycle = min(max(1, state.cycle), cycles)
        remaining = state.remaining(at: date) ?? 0
        if let end = state.phaseEndsAt, end > state.updatedAt {
            let length = end.timeIntervalSince(state.updatedAt)
            fraction = min(1, max(0, date.timeIntervalSince(state.updatedAt) / length))
        } else {
            fraction = 0
        }
    }

    var isBreak: Bool { phase.isBreak }

    /// Restzeit in angefangenen Minuten (wie Menüleiste und Popover: „noch 1 min“ bis zum Ende).
    var remainingMinutes: Int { max(0, Int((remaining / 60).rounded(.up))) }

    /// Beschriftung des Pomodoro-Strichs: „🍅 23 min“ bzw. „Pause 7 min“.
    var label: String {
        isBreak ? "Pause \(remainingMinutes) min" : "🍅 \(remainingMinutes) min"
    }

    /// Restzeit als Uhr ohne Sekunden-Takt: „7:00“, ab einer Stunde „1:05:00“.
    var clock: String {
        let minutes = remainingMinutes
        if minutes >= 60 { return String(format: "%d:%02d:00", minutes / 60, minutes % 60) }
        return "\(minutes):00"
    }

    /// „Pomodoro 2/4“.
    var cycleLabel: String { "Pomodoro \(cycle)/\(cycles)" }

    /// Bedienungshilfe: „Pomodoro 2 von 4, Arbeit, noch 23 Minuten“.
    var accessibilityText: String {
        "Pomodoro \(cycle) von \(cycles), \(phase.title), noch \(remainingMinutes) Minuten"
    }
}

struct Provider: AppIntentTimelineProvider {
    typealias Intent = TaktWidgetConfigurationIntent

    /// Wie weit eine Timeline mit laufendem Timer vorausplant.
    static let runningHorizon = 60
    /// Spätestens nach dieser Zeit wird im Pause-Zustand neu geladen.
    static let idleRefresh: TimeInterval = 3600

    func placeholder(in context: Context) -> TaktEntry {
        TaktEntry(date: .now, snapshot: Self.previewSnapshot(now: .now, fixedProjectID: nil), style: SharedSettings.widgetStyle)
    }

    func snapshot(for configuration: Intent, in context: Context) async -> TaktEntry {
        let now = Date.now
        let fixed = configuration.project?.id
        // In der Widget-Galerie Beispieldaten (mit den echten Projekten), sonst echte Daten.
        let snapshot = context.isPreview
            ? Self.previewSnapshot(now: now, fixedProjectID: fixed)
            : Self.loadSnapshot(now: now, fixedProjectID: fixed)
        return TaktEntry(date: now, snapshot: snapshot, style: configuration.style.resolved)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<TaktEntry> {
        let now = Date.now
        return Self.timeline(
            for: Self.loadSnapshot(now: now, fixedProjectID: configuration.project?.id),
            now: now,
            style: configuration.style.resolved
        )
    }

    // MARK: Bausteine

    /// Liest die Momentaufnahme; bei jedem Fehler „nichts läuft, keine Projekte“.
    static func loadSnapshot(now: Date, fixedProjectID: UUID? = nil) -> WidgetSnapshot {
        guard let database = WidgetDatabase.open() else { return .empty }
        do {
            return try database.widgetSnapshot(now: now, fixedProjectID: fixedProjectID)
        } catch {
            return .empty
        }
    }

    /// Läuft ein Timer: Eintrag jetzt, danach einer pro Minutengrenze der laufenden Dauer
    /// für die nächsten 60 Minuten, dann neu laden. Läuft nichts: ein Eintrag, neu laden nach
    /// einer Stunde bzw. um Mitternacht (Tagessumme beginnt bei 0); wird vorher ein geplanter
    /// Block fällig, kommt zu seinem Beginn ein zweiter Eintrag (Hervorhebung „Jetzt: …“).
    ///
    /// Läuft eine Pomodoro-Phase, kommen die Grenzen der Restminuten dazu (damit „23 min“ genau
    /// umspringt) und ein Eintrag zum Phasenende; dort endet die Timeline (`.atEnd`) – die App
    /// schreibt dann die nächste Phase und lädt ohnehin neu.
    /// Alle Einträge tragen denselben `style`; ein Wechsel in der App lädt die Timeline ohnehin neu.
    static func timeline(
        for snapshot: WidgetSnapshot,
        now: Date,
        style: WidgetStyle = .plain,
        calendar: Calendar = .current
    ) -> Timeline<TaktEntry> {
        let phaseEnd = pomodoroPhaseEnd(snapshot, now: now)

        func timeline(_ dates: [Date], horizon: Date, policy: TimelineReloadPolicy) -> Timeline<TaktEntry> {
            var dates = dates
            if let phaseEnd {
                dates += pomodoroMinuteBoundaries(phaseEnd: phaseEnd, now: now)
                if phaseEnd <= horizon { dates.append(phaseEnd) }
            }
            let cutoff = phaseEnd.map { min($0, horizon) } ?? horizon
            let sorted = dates.filter { $0 > now && $0 <= cutoff }.sorted()
            // Zeitpunkte, die weniger als eine Sekunde auseinanderliegen, zusammenfassen.
            var unique: [Date] = []
            for date in sorted where unique.last.map({ date.timeIntervalSince($0) >= 1 }) ?? true {
                unique.append(date)
            }
            let entries = [now] + unique
            let ends = phaseEnd.map { $0 <= horizon } ?? false
            return Timeline(
                entries: entries.map { TaktEntry(date: $0, snapshot: snapshot, snapshotDate: now, style: style) },
                policy: ends ? .atEnd : policy
            )
        }

        guard let running = snapshot.running else {
            let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
                ?? now.addingTimeInterval(idleRefresh)
            let refresh = min(now.addingTimeInterval(idleRefresh), midnight)
            var dates: [Date] = []
            if let block = snapshot.plannedBlock, block.startAt > now, block.startAt < refresh {
                dates.append(block.startAt)
            }
            return timeline(dates, horizon: refresh, policy: .after(refresh))
        }

        // Minutengrenzen relativ zum Start, damit „h:mm“ genau dann umspringt, wenn eine
        // volle Minute erreicht ist.
        let startedAt = running.entry.startedAt
        let elapsedMinutes = floor(max(0, now.timeIntervalSince(startedAt)) / 60)
        let following = (1...runningHorizon).map { offset in
            startedAt.addingTimeInterval((elapsedMinutes + Double(offset)) * 60)
        }
        return timeline(following, horizon: following.last ?? now, policy: .atEnd)
    }

    /// Ende der laufenden Pomodoro-Phase, falls der Modus an ist und die Phase noch läuft.
    static func pomodoroPhaseEnd(_ snapshot: WidgetSnapshot, now: Date) -> Date? {
        guard let state = snapshot.pomodoro, state.enabled, state.isActive(at: now) else { return nil }
        return state.phaseEndsAt
    }

    /// Zeitpunkte, zu denen die Restzeit in angefangenen Minuten umspringt (Ende − n Minuten).
    static func pomodoroMinuteBoundaries(phaseEnd: Date, now: Date) -> [Date] {
        let minutes = Int(max(0, phaseEnd.timeIntervalSince(now)) / 60)
        guard minutes > 0 else { return [] }
        return (1...minutes).map { phaseEnd.addingTimeInterval(-Double($0) * 60) }
    }

    // MARK: Galerie-Vorschau

    /// Vorschau mit den echten Projekten: das erste (bzw. das feste) Projekt läuft seit 1:24,
    /// davor bis zu zwei erledigte Blöcke anderer Projekte in der Tagesleiste.
    /// Ohne Projekte (oder ohne Datenbank) `WidgetSnapshot.placeholder`.
    static func previewSnapshot(now: Date, fixedProjectID: UUID?, calendar: Calendar = .current) -> WidgetSnapshot {
        guard let database = WidgetDatabase.open(),
              let active = try? database.activeProjects(), !active.isEmpty
        else { return .placeholder }

        var projects = active
        if let fixedProjectID {
            guard let fixed = active.first(where: { $0.id == fixedProjectID })
                ?? ((try? database.project(id: fixedProjectID)) ?? nil)
            else { return .placeholder }
            projects = [fixed]
        }
        let first = projects[0]
        let others = Array(projects.dropFirst())
        let startOfDay = calendar.startOfDay(for: now)

        let runningSince = now.addingTimeInterval(-(1 * 3600 + 24 * 60))
        let entry = TimeEntry(projectId: first.id, startedAt: runningSince)

        // Rückwärts vom laufenden Eintrag: drittes Projekt 0:35, davor zweites 2:00.
        let earlier: [(Project, TimeInterval)] = [
            others.dropFirst().first.map { ($0, 35 * 60) },
            others.first.map { ($0, 2 * 3600) },
        ].compactMap { $0 }
        var todayEntries: [WidgetSnapshot.TodayEntry] = []
        var completed: TimeInterval = 0
        var cursor = runningSince.addingTimeInterval(-10 * 60)
        for (project, length) in earlier {
            let start = max(startOfDay, cursor.addingTimeInterval(-length))
            guard start < cursor else { break }
            todayEntries.insert(
                WidgetSnapshot.TodayEntry(projectId: project.id, colorHex: project.colorHex, startedAt: start, endedAt: cursor),
                at: 0
            )
            completed += cursor.timeIntervalSince(start)
            cursor = start.addingTimeInterval(-15 * 60)
        }
        todayEntries.append(WidgetSnapshot.TodayEntry(
            projectId: first.id, colorHex: first.colorHex, startedAt: max(startOfDay, runningSince), endedAt: nil
        ))

        let budget: WidgetSnapshot.BudgetInfo? = first.budgetInterval.map { interval in
            let used = (try? database.budgetUsage(projectId: first.id, now: now).used) ?? 0
            return WidgetSnapshot.BudgetInfo(used: used + entry.duration(at: now), budget: interval, completed: used)
        }
        var planned: WidgetSnapshot.PlannedBlockInfo?
        if let block = (try? database.plannedBlock(now: now)) ?? nil,
           let project = projects.first(where: { $0.id == block.projectId }) {
            planned = WidgetSnapshot.PlannedBlockInfo(project: project, startAt: block.startAt, note: block.note)
        }

        return WidgetSnapshot(
            running: RunningState(project: first, entry: entry),
            recent: Array(others.prefix(WidgetSnapshot.maxRecent)),
            todayCompleted: completed,
            switchTargets: Array(others.prefix(WidgetSnapshot.maxSwitchTargets)),
            allProjects: projects,
            todayEntries: todayEntries,
            runningNextStep: (try? database.lastNextStep(projectId: first.id)) ?? nil,
            plannedBlock: planned,
            breakReminderMinutes: SharedSettings.breakReminderMinutesIfEnabled(in: SharedSettings.defaults),
            runningBudget: budget,
            fixedProjectID: fixedProjectID
        )
    }
}
