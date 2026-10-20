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
    /// Letzte Fehlermeldung; die Oberfläche zeigt sie als Hinweis an.
    var lastError: String?

    // MARK: Interna

    @ObservationIgnored private let database: AppDatabase?
    @ObservationIgnored private var changeObservation: ChangeObservation?
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []
    /// Reagieren auf Timer-Übergänge (Musik, Pausenerinnerung); siehe `attach`.
    @ObservationIgnored private var musicController: MusicController?
    @ObservationIgnored private var breakReminder: BreakReminder?

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
        breakReminder.resume(with: running)
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

            let focus = try database.focusStats(in: today, now: now)
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
            let previous = running
            if running != runningState { running = runningState }
            notifyTimerChangeIfNeeded(from: previous, to: runningState)
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

    @discardableResult
    func stop(nextStep: String?) -> Bool {
        write { try $0.stopTimer(nextStep: nextStep) }
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
    func report(for period: ReportPeriod, rounding: Rounding, defaultHourlyRate: Decimal?, now: Date = .now) -> Report? {
        guard let database else { return nil }
        do {
            return try database.report(for: period, rounding: rounding, defaultHourlyRate: defaultHourlyRate, now: now)
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

    // MARK: Hilfen

    /// Führt eine Schreiboperation aus; Fehler landen in `lastError`, nie ein Absturz.
    /// Danach: neu laden, andere Prozesse benachrichtigen, Widget-Timelines neu laden.
    @discardableResult
    private func write(_ operation: (AppDatabase) throws -> Void) -> Bool {
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
        WidgetCenter.shared.reloadAllTimelines()
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
