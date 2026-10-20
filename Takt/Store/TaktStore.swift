import AppKit
import Foundation
import Observation
import TaktCore
import WidgetKit

/// Zentraler Zustand der Hauptapp. Liest alles aus der gemeinsamen SQLite-Datenbank und
/// stößt nach jeder Änderung Widget und andere Prozesse an.
@MainActor
@Observable
final class TaktStore {
    // MARK: Zustand

    /// Aktive (nicht archivierte) Projekte in manueller Reihenfolge.
    private(set) var projects: [Project] = []
    private(set) var archivedProjects: [Project] = []
    /// Alle Projekte nach ID, auch archivierte (für Einträge archivierter Projekte).
    private(set) var projectsById: [UUID: Project] = [:]
    private(set) var running: RunningState?
    /// Heutige Einträge, neueste zuerst (der laufende eingeschlossen).
    private(set) var todayEntries: [TimeEntry] = []
    /// Summe heute ohne den laufenden Eintrag, auf den heutigen Tag zugeschnitten.
    private(set) var todayCompleted: TimeInterval = 0
    /// „Nächster Schritt“ des zuletzt beendeten Eintrags je aktivem Projekt.
    private(set) var lastNextSteps: [UUID: String] = [:]
    /// Fokus-Kennzahlen für heute (Projektwechsel, längster Block).
    private(set) var todayFocus = FocusStats(switches: 0, longestBlock: 0)
    /// Zuletzt beendetes aktives Projekt („Weiter mit …“); `nil`, solange etwas läuft.
    private(set) var lastUsedProject: Project?
    /// Der geplante „nächste Block“ (bis 4 h nach Beginn), sonst `nil`.
    private(set) var plannedBlock: PlannedBlock?
    /// Verbrauchte Zeit in abgeschlossenen Einträgen (alle Tage) je Projekt mit Stundenbudget.
    /// Der laufende Eintrag fehlt hier; siehe `budgetUsed(projectId:at:)`.
    private(set) var budgetCompleted: [UUID: TimeInterval] = [:]
    /// Kalender-Regeln in Prüfreihenfolge (v5).
    private(set) var calendarRules: [CalendarRule] = []
    /// Aktivitäts-Regeln in Prüfreihenfolge (v5).
    private(set) var activityRules: [ActivityRule] = []
    /// Letzte Fehlermeldung; die Oberfläche zeigt sie als Hinweis an.
    var lastError: String?

    // MARK: Interna

    @ObservationIgnored private let database: AppDatabase?
    @ObservationIgnored private var changeObservation: ChangeObservation?
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []
    /// Reagieren auf Timer-Übergänge (Musik, Pausenerinnerung); siehe `attach`.
    @ObservationIgnored private var musicController: MusicController?
    @ObservationIgnored private var breakReminder: BreakReminder?
    /// Projektname, mit dem der geplante Block zuletzt an die Erinnerung gemeldet wurde.
    @ObservationIgnored private var notifiedPlannedName: String?

    /// Öffnet die Datenbank selbst statt über `AppDatabase.shared`, weil `shared` bei einem
    /// Fehler per `fatalError` abbricht – die App soll stattdessen einen Hinweis zeigen.
    init(database: AppDatabase? = nil) {
        var openError: String?
        if let database {
            self.database = database
        } else {
            do {
                self.database = try AppDatabase.onDisk(at: AppDatabase.defaultURL())
            } catch {
                self.database = nil
                openError = "Die Datenbank konnte nicht geöffnet werden: \(error.localizedDescription)"
            }
        }

        if let openError {
            lastError = openError
            return
        }

        refresh()
        startObserving()
    }

    /// Verbindet Musiksteuerung und Pausenerinnerung. Ein beim App-Start bereits laufender
    /// Timer gilt nicht als Start: Die Musik bleibt unberührt, nur die Erinnerung wird
    /// (falls noch ausstehend) wieder eingeplant.
    func attach(musicController: MusicController, breakReminder: BreakReminder) {
        self.musicController = musicController
        self.breakReminder = breakReminder
        // Aktion „Starten“ der Mitteilung zum geplanten Block.
        breakReminder.startPlannedBlock = { [weak self] blockId in
            guard let self, self.plannedBlock?.id == blockId else { return }
            self.startPlannedBlock()
        }
        breakReminder.resume(with: running)
        notifyPlannedBlockChange()
    }

    // MARK: Laden

    /// Liest den gesamten angezeigten Zustand neu aus der Datenbank.
    func refresh() {
        guard let database else { return }
        do {
            let now = Date.now
            let calendar = Calendar.current
            let today = calendar.dateInterval(of: .day, for: now)
                ?? DateInterval(start: calendar.startOfDay(for: now), duration: 24 * 3600)

            let all = try database.allProjects()
            let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let active = all.filter { !$0.isArchived }

            var steps: [UUID: String] = [:]
            for project in active {
                if let step = try database.lastNextStep(projectId: project.id) {
                    steps[project.id] = step
                }
            }

            let entries = try database.entries(in: today)
            let completed = entries
                .filter { !$0.isRunning }
                .reduce(0) { $0 + Self.clippedDuration($1, to: today) }

            var runningState: RunningState?
            if let entry = try database.activeEntry(), let project = byId[entry.projectId] {
                runningState = RunningState(project: project, entry: entry)
            }

            let block = try database.plannedBlock(now: now)
            var budgets: [UUID: TimeInterval] = [:]
            for project in all where project.budgetInterval != nil {
                let used = try database.budgetUsage(projectId: project.id, now: now).used
                // Laufenden Anteil abziehen – die Ansicht rechnet ihn minütlich selbst dazu.
                let runningPart = runningState?.project.id == project.id ? runningState?.entry.duration(at: now) ?? 0 : 0
                budgets[project.id] = max(0, used - runningPart)
            }

            let focus = try database.focusStats(in: today, now: now)
            let calRules = try database.calendarRules()
            let actRules = try database.activityRules()
            var lastUsed: Project?
            if runningState == nil {
                lastUsed = try Self.lastUsedProject(database, todayEntries: entries, byId: byId, now: now)
            }

            // Nur bei echten Änderungen zuweisen, damit SwiftUI nicht unnötig neu zeichnet.
            if projects != active { projects = active }
            let archived = all.filter(\.isArchived)
            if archivedProjects != archived { archivedProjects = archived }
            if projectsById != byId { projectsById = byId }
            if lastNextSteps != steps { lastNextSteps = steps }
            let newest = Array(entries.reversed())
            if todayEntries != newest { todayEntries = newest }
            if todayCompleted != completed { todayCompleted = completed }
            if todayFocus != focus { todayFocus = focus }
            if lastUsedProject != lastUsed { lastUsedProject = lastUsed }
            if budgetCompleted != budgets { budgetCompleted = budgets }
            if calendarRules != calRules { calendarRules = calRules }
            if activityRules != actRules { activityRules = actRules }
            let blockName = block.flatMap { byId[$0.projectId]?.name }
            let blockChanged = plannedBlock != block || notifiedPlannedName != blockName
            if plannedBlock != block { plannedBlock = block }
            let previous = running
            if running != runningState { running = runningState }
            notifyTimerChangeIfNeeded(from: previous, to: runningState)
            // Nach dem Timer-Wechsel, damit die Erinnerung den aktuellen Lauf-Zustand kennt.
            if blockChanged { notifyPlannedBlockChange() }
        } catch {
            lastError = Self.message(for: error)
        }
    }

    /// Lädt nur die Fokus-Kennzahlen neu – minütlich, solange ein Timer läuft
    /// (der längste Block wächst mit).
    func refreshFocus(at now: Date = .now) {
        guard let database else { return }
        let calendar = Calendar.current
        guard let today = calendar.dateInterval(of: .day, for: now) else { return }
        do {
            let focus = try database.focusStats(in: today, now: now)
            if todayFocus != focus { todayFocus = focus }
        } catch {
            lastError = Self.message(for: error)
        }
    }

    /// Projekt zu einer ID, auch archivierte.
    func project(id: UUID) -> Project? {
        projectsById[id]
    }

    /// Heutige Gesamtzeit inklusive des laufenden Eintrags (dessen heutiger Anteil).
    func todayTotal(at now: Date) -> TimeInterval {
        guard let entry = running?.entry else { return todayCompleted }
        let startOfDay = Calendar.current.startOfDay(for: now)
        let runningToday = max(0, now.timeIntervalSince(max(entry.startedAt, startOfDay)))
        return todayCompleted + runningToday
    }

    /// Heutige Zeit eines Projekts inklusive laufendem Eintrag, auf heute zugeschnitten.
    func todayTotal(projectId: UUID, at now: Date) -> TimeInterval {
        let calendar = Calendar.current
        guard let today = calendar.dateInterval(of: .day, for: now) else { return 0 }
        return todayEntries
            .filter { $0.projectId == projectId }
            .reduce(0) { total, entry in
                let start = max(entry.startedAt, today.start)
                let end = max(start, min(entry.endedAt ?? now, today.end))
                return total + end.timeIntervalSince(start)
            }
    }

    /// Verbrauchte Zeit eines Projekts mit Budget (alle Einträge, laufender bis `now`);
    /// `nil` für Projekte ohne Budget.
    func budgetUsed(projectId: UUID, at now: Date) -> TimeInterval? {
        guard let completed = budgetCompleted[projectId] else { return nil }
        guard let entry = running?.entry, entry.projectId == projectId else { return completed }
        return completed + entry.duration(at: now)
    }

    /// Nächste freie Sortierposition für ein neues Projekt.
    var nextSortOrder: Int {
        ((projects + archivedProjects).map(\.sortOrder).max() ?? -1) + 1
    }

    /// Gibt die letzte Fehlermeldung zurück und setzt sie zurück
    /// (für Sheets, die den Fehler selbst anzeigen).
    func consumeError() -> String? {
        defer { lastError = nil }
        return lastError
    }

    // MARK: Timer

    @discardableResult
    func start(projectId: UUID) -> Bool {
        write { try $0.startTimer(projectId: projectId) }
    }

    /// Startet das Projekt mit Tag (läuft es schon, bekommt der laufende Eintrag den Tag).
    @discardableResult
    func start(projectId: UUID, tag: String?) -> Bool {
        write { try $0.startTimer(projectId: projectId, tag: tag) }
    }

    @discardableResult
    func stop(nextStep: String?) -> Bool {
        write { try $0.stopTimer(nextStep: nextStep) }
    }

    /// Stoppt mit ausdrücklichem Ende, z. B. „Leerlauf abziehen“ (Ende = Beginn des Leerlaufs).
    @discardableResult
    func stop(at end: Date, nextStep: String?) -> Bool {
        write { try $0.stopTimer(at: end, nextStep: nextStep) }
    }

    /// Verwirft den laufenden Eintrag ganz (z. B. abgebrochene Pomodoro-Einheit).
    @discardableResult
    func discardRunning() -> Bool {
        write { try $0.discardRunning() }
    }

    // MARK: Tags

    /// Tag-Vorschläge (zuerst des Projekts, dann alle, zuletzt genutzte zuerst); bei Fehlern leer.
    func tagSuggestions(projectId: UUID?, prefix: String, limit: Int = 8) -> [String] {
        (try? database?.tagSuggestions(projectId: projectId, prefix: prefix, limit: limit)) ?? []
    }

    // MARK: Freie Tage

    /// Freie Tage im Intervall (nach Datum); bei Fehlern leer (Meldung in `lastError`).
    func daysOff(in interval: DateInterval) -> [DayOff] {
        guard let database else { return [] }
        do {
            return try database.daysOff(in: interval)
        } catch {
            lastError = Self.message(for: error)
            return []
        }
    }

    /// Markiert den Kalendertag von `date` als frei (ersetzt eine vorhandene Markierung).
    @discardableResult
    func setDayOff(date: Date, kind: DayOffKind, note: String? = nil) -> Bool {
        write { try $0.setDayOff(date: date, kind: kind, note: note) }
    }

    @discardableResult
    func removeDayOff(date: Date) -> Bool {
        write { try $0.removeDayOff(date: date) }
    }

    func isDayOff(date: Date) -> Bool {
        (try? database?.isDayOff(date: date)) ?? false
    }

    // MARK: Schnelleingabe

    /// Liest eine Schnelleingabe gegen die aktiven Projekte, z. B. „kunden 9-10:30 #meeting Standup“.
    func quickEntry(_ text: String, now: Date = .now) -> Result<QuickEntry, QuickEntryError> {
        QuickEntryParser.parse(text, projects: projects, now: now)
    }

    /// Übernimmt eine Schnelleingabe: fertiger Eintrag wird angelegt, ein Timer-Start startet das
    /// Projekt mit Tag (ein laufender Timer eines anderen Projekts endet zum Start). Liegt der
    /// Start mehr als eine Minute zurück („seit 9:30“), beginnt der Timer rückwirkend.
    /// Die Notiz landet als „Nächster Schritt“ im Eintrag.
    @discardableResult
    func commit(_ quick: QuickEntry) -> Bool {
        guard let projectId = quick.projectId else {
            lastError = QuickEntryError.missingProject.errorDescription
            return false
        }
        if quick.isRunningStart {
            let now = Date.now
            let start = quick.start < now.addingTimeInterval(-60) ? quick.start : now
            return write { database in
                var running = try database.startTimer(projectId: projectId, tag: quick.tag, now: start)
                if let note = quick.note, running.nextStep == nil {
                    running.nextStep = note
                    try database.updateEntry(running)
                }
            }
        }
        let entry = TimeEntry(
            projectId: projectId,
            startedAt: quick.start,
            endedAt: quick.end ?? .now,
            nextStep: quick.note,
            tag: quick.tag
        )
        return write { try $0.addEntry(entry) }
    }

    // MARK: Geplanter Block

    /// Plant den nächsten Block (ersetzt einen vorhandenen).
    @discardableResult
    func planBlock(projectId: UUID, startAt: Date, note: String?) -> Bool {
        write { try $0.setPlannedBlock(projectId: projectId, startAt: startAt, note: note) }
    }

    @discardableResult
    func clearPlannedBlock() -> Bool {
        write { try $0.clearPlannedBlock() }
    }

    /// Startet das Projekt des geplanten Blocks jetzt; der Block ist damit erledigt –
    /// auch wenn er erst später geplant war.
    @discardableResult
    func startPlannedBlock() -> Bool {
        guard let block = plannedBlock else { return false }
        return write { database in
            try database.startTimer(projectId: block.projectId)
            try database.clearPlannedBlock()
        }
    }

    // MARK: Projekte

    @discardableResult
    func saveProject(_ project: Project) -> Bool {
        write { try $0.saveProject(project) }
    }

    @discardableResult
    func archive(_ project: Project) -> Bool {
        write { try $0.archiveProject(id: project.id) }
    }

    @discardableResult
    func unarchive(_ project: Project) -> Bool {
        write { try $0.unarchiveProject(id: project.id) }
    }

    /// Verschiebt aktive Projekte (Signatur passend zu `onMove`).
    func reorder(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = projects
        reordered.move(fromOffsets: source, toOffset: destination)
        // Sofort lokal übernehmen, damit die Liste beim Loslassen nicht zurückspringt.
        projects = reordered
        write { try $0.reorderProjects(ids: reordered.map(\.id)) }
    }

    // MARK: Einträge

    @discardableResult
    func addEntry(_ entry: TimeEntry) -> Bool {
        write { try $0.addEntry(entry) }
    }

    @discardableResult
    func updateEntry(_ entry: TimeEntry) -> Bool {
        write { try $0.updateEntry(entry) }
    }

    @discardableResult
    func deleteEntry(_ entry: TimeEntry) -> Bool {
        write { try $0.deleteEntry(id: entry.id) }
    }

    // MARK: Berichte & Import

    /// Bericht für einen Zeitraum; bei Fehlern `nil` (Meldung in `lastError`).
    /// `weeklyGoal` (Sekunden) kommt standardmäßig aus den Einstellungen (über `SharedSettings`
    /// gespiegelt); `nil` = kein Ziel.
    func report(
        for period: ReportPeriod,
        rounding: Rounding,
        defaultHourlyRate: Decimal?,
        weeklyGoal: TimeInterval? = TaktStore.settingsWeeklyGoal,
        now: Date = .now
    ) -> Report? {
        guard let database else { return nil }
        do {
            return try database.report(
                for: period, rounding: rounding, defaultHourlyRate: defaultHourlyRate,
                weeklyGoal: weeklyGoal, now: now
            )
        } catch {
            lastError = Self.message(for: error)
            return nil
        }
    }

    /// Einträge, die sich mit dem Intervall überschneiden (z. B. für den CSV-Export).
    func entries(in interval: DateInterval) -> [TimeEntry] {
        guard let database else { return [] }
        do {
            return try database.entries(in: interval)
        } catch {
            lastError = Self.message(for: error)
            return []
        }
    }

    /// Vorschlag Toggl-Projekt → vorhandenes Projekt (gleicher Name), sonst `nil` = neu.
    func suggestedTogglMapping(for preview: TogglImportPreview) -> [String: UUID?] {
        (try? database?.suggestedTogglMapping(for: preview)) ?? [:]
    }

    /// Importiert die Toggl-Vorschau; gibt die Zahl neuer Einträge zurück, bei Fehlern `nil`.
    func importToggl(_ preview: TogglImportPreview, projectMapping: [String: UUID?], markAsBusiness: Bool) -> Int? {
        var inserted = 0
        let ok = write {
            inserted = try $0.importToggl(preview, projectMapping: projectMapping, markAsBusiness: markAsBusiness)
        }
        return ok ? inserted : nil
    }

    // MARK: Jahresbericht & Budget (v5)

    /// Jahresbericht (Monate, Kunden, Projekte, Tags, Vorjahr); bei Fehlern `nil` (Meldung in `lastError`).
    func yearReport(year: Int, rounding: Rounding, defaultHourlyRate: Decimal?, now: Date = .now) -> YearReport? {
        read { try $0.yearReport(year: year, rounding: rounding, defaultHourlyRate: defaultHourlyRate, now: now) }
    }

    /// Budgetverbrauch aller aktiven Projekte mit Budget (für Budget-Warnungen); bei Fehlern leer.
    func budgetUsages(now: Date = .now) -> [BudgetUsage] {
        read { try $0.budgetUsages(now: now) } ?? []
    }

    // MARK: Kalender (v5)

    func calendarLink(entryId: UUID) -> CalendarEventLink? {
        read { try $0.calendarLink(entryId: entryId) } ?? nil
    }

    /// Merkt sich das gespiegelte Ereignis eines Eintrags (ersetzt eine vorhandene Verknüpfung).
    @discardableResult
    func setCalendarLink(_ link: CalendarEventLink) -> Bool {
        write(reloadWidgets: false) { try $0.setCalendarLink(link) }
    }

    @discardableResult
    func removeCalendarLink(entryId: UUID) -> Bool {
        write(reloadWidgets: false) { try $0.removeCalendarLink(entryId: entryId) }
    }

    /// Abgeschlossene Einträge, die (neu) gespiegelt werden müssen; bei Fehlern leer.
    func entriesNeedingMirror(since: Date, minimumDuration: TimeInterval) -> [TimeEntry] {
        read { try $0.entriesNeedingMirror(since: since, minimumDuration: minimumDuration) } ?? []
    }

    /// Entfernt verwaiste Verknüpfungen und gibt sie zurück (deren Ereignisse löscht der Aufrufer).
    @discardableResult
    func removeOrphanCalendarLinks() -> [CalendarEventLink] {
        var removed: [CalendarEventLink] = []
        write(reloadWidgets: false) { removed = try $0.removeOrphanLinks() }
        return removed
    }

    @discardableResult
    func addCalendarRule(kind: CalendarRuleKind, pattern: String, projectId: UUID) -> Bool {
        write(reloadWidgets: false) { try $0.addCalendarRule(kind: kind, pattern: pattern, projectId: projectId) }
    }

    @discardableResult
    func saveCalendarRule(_ rule: CalendarRule) -> Bool {
        write(reloadWidgets: false) { try $0.saveCalendarRule(rule) }
    }

    @discardableResult
    func deleteCalendarRule(_ rule: CalendarRule) -> Bool {
        write(reloadWidgets: false) { try $0.deleteCalendarRule(id: rule.id) }
    }

    /// Verschiebt Kalender-Regeln (Signatur passend zu `onMove`).
    func reorderCalendarRules(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = calendarRules
        reordered.move(fromOffsets: source, toOffset: destination)
        calendarRules = reordered
        write(reloadWidgets: false) { try $0.reorderCalendarRules(ids: reordered.map(\.id)) }
    }

    /// Projekt der ersten passenden Kalender-Regel; ohne Treffer oder bei Fehlern `nil`.
    func matchCalendarRule(calendarName: String?, title: String?, attendeeDomains: [String]) -> Project? {
        read { try $0.matchCalendarRule(calendarName: calendarName, title: title, attendeeDomains: attendeeDomains) } ?? nil
    }

    // MARK: Aktivität (v5)

    @discardableResult
    func addActivityRule(kind: ActivityRuleKind, pattern: String, projectId: UUID) -> Bool {
        write(reloadWidgets: false) { try $0.addActivityRule(kind: kind, pattern: pattern, projectId: projectId) }
    }

    @discardableResult
    func saveActivityRule(_ rule: ActivityRule) -> Bool {
        write(reloadWidgets: false) { try $0.saveActivityRule(rule) }
    }

    @discardableResult
    func deleteActivityRule(_ rule: ActivityRule) -> Bool {
        write(reloadWidgets: false) { try $0.deleteActivityRule(id: rule.id) }
    }

    /// Verschiebt Aktivitäts-Regeln (Signatur passend zu `onMove`).
    func reorderActivityRules(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = activityRules
        reordered.move(fromOffsets: source, toOffset: destination)
        activityRules = reordered
        write(reloadWidgets: false) { try $0.reorderActivityRules(ids: reordered.map(\.id)) }
    }

    /// Projekt der ersten passenden Aktivitäts-Regel; ohne Treffer oder bei Fehlern `nil`.
    func matchActivityRule(bundleID: String?, windowTitle: String?, repoPath: String?) -> Project? {
        read { try $0.matchActivityRule(bundleID: bundleID, windowTitle: windowTitle, repoPath: repoPath) } ?? nil
    }

    /// Speichert beobachtete Aktivität (Projekt per Regel ermittelt, ältere als 30 Tage fallen weg).
    /// Bewusst ohne `refresh()`, Benachrichtigung und Widget-Reload: Proben kommen häufig und
    /// ändern nichts Angezeigtes. Gibt die gespeicherte Probe zurück, bei Fehlern `nil`.
    @discardableResult
    func addActivitySample(_ sample: ActivitySample) -> ActivitySample? {
        guard let database else { return nil }
        do {
            return try database.addActivitySample(sample)
        } catch {
            lastError = Self.message(for: error)
            return nil
        }
    }

    /// Beobachtete Aktivität im Intervall; bei Fehlern leer.
    func activitySamples(in interval: DateInterval) -> [ActivitySample] {
        read { try $0.activitySamples(in: interval) } ?? []
    }

    /// Löscht Aktivität, die vor `date` endet (still wie `addActivitySample`).
    @discardableResult
    func pruneActivitySamples(olderThan date: Date) -> Int {
        guard let database else { return 0 }
        do {
            return try database.pruneActivitySamples(olderThan: date)
        } catch {
            lastError = Self.message(for: error)
            return 0
        }
    }

    // MARK: Hilfen

    /// Wochenziel aus den Einstellungen in Sekunden (`AppSettings.weeklyGoalHours`, gespiegelt
    /// nach `SharedSettings`); `nil` ohne Ziel.
    nonisolated static var settingsWeeklyGoal: TimeInterval? {
        SharedSettings.weeklyGoal(in: SharedSettings.defaults)
    }

    /// Führt eine Leseabfrage aus; Fehler landen in `lastError` und ergeben `nil`.
    private func read<T>(_ operation: (AppDatabase) throws -> T) -> T? {
        guard let database else { return nil }
        do {
            return try operation(database)
        } catch {
            lastError = Self.message(for: error)
            return nil
        }
    }

    /// Führt eine Schreiboperation aus; Fehler landen in `lastError`, nie ein Absturz.
    /// Danach: neu laden, andere Prozesse benachrichtigen und – sofern `reloadWidgets` – die
    /// Widget-Timelines neu laden (Regeln und Kalender-Verknüpfungen zeigt das Widget nicht).
    @discardableResult
    private func write(reloadWidgets: Bool = true, _ operation: (AppDatabase) throws -> Void) -> Bool {
        guard let database else {
            lastError = "Die Datenbank ist nicht verfügbar."
            return false
        }
        do {
            try operation(database)
        } catch {
            lastError = Self.message(for: error)
            refresh()
            return false
        }
        refresh()
        ChangeNotifier.post()
        if reloadWidgets { WidgetCenter.shared.reloadAllTimelines() }
        return true
    }

    /// Meldet einen Wechsel des laufenden Eintrags (nil→X, X→nil, X→Y) genau einmal – egal ob
    /// er aus der App, dem Widget oder einem anderen Prozess stammt. Weitere `refresh()`-Aufrufe
    /// ohne Wechsel (z. B. durch die eigene Darwin-Notification) lösen nichts aus.
    /// Wechselt beim laufenden Eintrag nachträglich das Projekt, zählt das ebenfalls als Wechsel.
    private func notifyTimerChangeIfNeeded(from old: RunningState?, to new: RunningState?) {
        guard old?.entry.id != new?.entry.id || old?.project.id != new?.project.id else { return }
        musicController?.timerDidChange(from: old, to: new)
        breakReminder?.timerDidChange(from: old, to: new)
    }

    /// Meldet den (neuen) geplanten Block an die Erinnerung, die daraus eine Mitteilung plant.
    private func notifyPlannedBlockChange() {
        let projectName = plannedBlock.flatMap { projectsById[$0.projectId]?.name }
        notifiedPlannedName = projectName
        breakReminder?.plannedBlockDidChange(plannedBlock, projectName: projectName)
    }

    private func startObserving() {
        // Änderungen aus dem Widget (oder eigene) – Darwin-Notification kommt auf dem Main-Thread an.
        changeObservation = ChangeNotifier.observe { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }

        let center = NotificationCenter.default
        // Beim Aktivieren neu laden, z. B. nach Änderungen während die App im Hintergrund war.
        notificationTokens.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        // Tageswechsel: „Heute“ beginnt neu.
        notificationTokens.append(center.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        // Der Store lebt so lange wie die App; ein Abmelden im deinit ist daher nicht nötig.
    }

    /// Projekt des zuletzt beendeten Eintrags, sofern es nicht archiviert ist. Meist reicht der
    /// heutige Tag; nur vor dem ersten Eintrag des Tages wird weiter zurückgeschaut.
    private static func lastUsedProject(
        _ database: AppDatabase,
        todayEntries: [TimeEntry],
        byId: [UUID: Project],
        now: Date
    ) throws -> Project? {
        func active(_ entry: TimeEntry?) -> Project? {
            guard let entry, let project = byId[entry.projectId], !project.isArchived else { return nil }
            return project
        }
        let lastToday = todayEntries.last { !$0.isRunning }
        if lastToday != nil { return active(lastToday) }
        let lookback = DateInterval(start: now.addingTimeInterval(-30 * 24 * 3600), end: now)
        return active(try database.entries(in: lookback).last { !$0.isRunning })
    }

    /// Dauer des Eintrags innerhalb des Intervalls; laufende Einträge enden jetzt.
    private static func clippedDuration(_ entry: TimeEntry, to interval: DateInterval) -> TimeInterval {
        let start = max(entry.startedAt, interval.start)
        let end = max(start, min(entry.endedAt ?? .now, interval.end))
        return end.timeIntervalSince(start)
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
