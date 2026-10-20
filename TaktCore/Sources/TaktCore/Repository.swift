import Foundation
import GRDB

/// Fokus-Kennzahlen für einen Zeitraum.
public struct FocusStats: Hashable, Sendable {
    /// Anzahl der Projektwechsel zwischen aufeinanderfolgenden Einträgen.
    public var switches: Int
    /// Längster zusammenhängender Block eines Projekts (vom ersten Start bis zum letzten Ende,
    /// kurze Lücken ≤ `mergeGap` eingeschlossen).
    public var longestBlock: TimeInterval

    /// Lücken bis zu dieser Länge zwischen Einträgen desselben Projekts verschmelzen zu einem Block.
    public static let mergeGap: TimeInterval = 5 * 60

    public init(switches: Int, longestBlock: TimeInterval) {
        self.switches = switches
        self.longestBlock = longestBlock
    }
}

// MARK: - Öffentliche API

extension AppDatabase {
    // MARK: Projekte

    /// Nicht archivierte Projekte in manueller Reihenfolge.
    public func activeProjects() throws -> [Project] {
        try writer.read { db in
            try Project
                .filter(Project.Columns.isArchived == false)
                .order(Project.Columns.sortOrder, Project.Columns.name)
                .fetchAll(db)
        }
    }

    /// Alle Projekte inklusive archivierter, in manueller Reihenfolge.
    public func allProjects() throws -> [Project] {
        try writer.read { db in
            try Project.order(Project.Columns.sortOrder, Project.Columns.name).fetchAll(db)
        }
    }

    public func project(id: UUID) throws -> Project? {
        try writer.read { db in try Project.fetchOne(db, id: id) }
    }

    /// Legt das Projekt an oder aktualisiert es.
    public func saveProject(_ project: Project) throws {
        try writer.write { db in try project.save(db) }
    }

    public func archiveProject(id: UUID) throws {
        try setArchived(true, id: id)
    }

    public func unarchiveProject(id: UUID) throws {
        try setArchived(false, id: id)
    }

    /// Setzt `sortOrder` gemäß der Position in `ids` (0, 1, 2, …).
    /// Nicht aufgeführte Projekte bleiben unverändert.
    public func reorderProjects(ids: [UUID]) throws {
        try writer.write { db in
            for (index, id) in ids.enumerated() {
                try Project
                    .filter(id: id)
                    .updateAll(db, Project.Columns.sortOrder.set(to: index))
            }
        }
    }

    // MARK: Timer

    /// Der laufende Eintrag, falls vorhanden.
    public func activeEntry() throws -> TimeEntry? {
        try writer.read { db in try Self.activeEntry(db) }
    }

    /// Startet einen Timer für das Projekt. Ein laufender Timer eines anderen Projekts wird
    /// dabei zum Zeitpunkt `now` beendet. Läuft das Projekt bereits, bleibt alles unverändert
    /// und der laufende Eintrag wird zurückgegeben.
    @discardableResult
    public func startTimer(projectId: UUID, now: Date = .now) throws -> TimeEntry {
        try writer.write { db in
            guard try Project.exists(db, id: projectId) else { throw TaktError.projectNotFound }
            // Ein fälliger geplanter Block dieses Projekts ist mit dem Start erledigt.
            try Self.deleteDuePlannedBlocks(db, projectId: projectId, now: now)
            if var running = try Self.activeEntry(db) {
                if running.projectId == projectId { return running }
                running.endedAt = max(now, running.startedAt)
                try running.update(db)
            }
            let entry = TimeEntry(projectId: projectId, startedAt: now)
            try entry.insert(db)
            return entry
        }
    }

    /// Beendet den laufenden Timer. `nextStep` wird getrimmt; leer bzw. nur Leerraum wird zu `nil`.
    /// Gibt `nil` zurück, wenn nichts lief.
    @discardableResult
    public func stopTimer(nextStep: String? = nil, now: Date = .now) throws -> TimeEntry? {
        try writer.write { db in
            guard var running = try Self.activeEntry(db) else { return nil }
            running.endedAt = max(now, running.startedAt)
            running.nextStep = Self.normalizedNote(nextStep)
            try running.update(db)
            return running
        }
    }

    /// „Nächster Schritt“ des zuletzt beendeten Eintrags dieses Projekts.
    public func lastNextStep(projectId: UUID) throws -> String? {
        try writer.read { db in try Self.lastNextStep(db, projectId: projectId) }
    }

    /// Nicht archivierte Projekte, zuletzt genutzte zuerst (jüngster Start), danach nie genutzte
    /// in manueller Reihenfolge. Einträge, die nach `now` beginnen, zählen nicht.
    /// Das laufende Projekt ist enthalten – das Ausblenden ist Sache der Oberfläche.
    public func recentProjects(limit: Int, now: Date = .now) throws -> [Project] {
        try writer.read { db in try Self.recentProjects(db, limit: limit, now: now) }
    }

    // MARK: Geplanter Block

    /// Wie lange ein geplanter Block nach seinem Beginn noch als „nächster Block“ gilt –
    /// damit ein gerade fälliger Block noch angezeigt (und gestartet) werden kann.
    public static let plannedBlockGrace: TimeInterval = 4 * 3600

    /// Bis zu diesem Abstand vor dem geplanten Beginn gilt ein Block beim Start als fällig
    /// und wird von `startTimer` gelöscht.
    public static let plannedBlockLeadTime: TimeInterval = 15 * 60

    /// Der geplante Block, sofern er nicht älter als `plannedBlockGrace` ist
    /// (`startAt >= now - 4 h`). Ältere werden ignoriert (und beim nächsten Setzen gelöscht).
    public func plannedBlock(now: Date = .now) throws -> PlannedBlock? {
        try writer.read { db in try Self.plannedBlock(db, now: now) }
    }

    /// Plant den nächsten Block und ersetzt dabei alle vorhandenen. `note` wird getrimmt;
    /// leer wird zu `nil`.
    /// - Throws: `TaktError.projectNotFound`.
    @discardableResult
    public func setPlannedBlock(projectId: UUID, startAt: Date, note: String? = nil, now: Date = .now) throws -> PlannedBlock {
        try writer.write { db in
            guard try Project.exists(db, id: projectId) else { throw TaktError.projectNotFound }
            try PlannedBlock.deleteAll(db)
            let block = PlannedBlock(projectId: projectId, startAt: startAt, note: Self.normalizedNote(note), createdAt: now)
            try block.insert(db)
            return block
        }
    }

    /// Entfernt den geplanten Block (alle, falls es durch Altbestände mehrere gäbe).
    public func clearPlannedBlock() throws {
        try writer.write { db in _ = try PlannedBlock.deleteAll(db) }
    }

    // MARK: Budget

    /// Verbrauchte Zeit des Projekts über alle Einträge (nicht nur heute; laufende bis `now`)
    /// und sein Budget in Sekunden (`nil` = kein Budget).
    /// - Throws: `TaktError.projectNotFound`.
    public func budgetUsage(projectId: UUID, now: Date = .now) throws -> (used: TimeInterval, budget: TimeInterval?) {
        try writer.read { db in
            guard let project = try Project.fetchOne(db, id: projectId) else { throw TaktError.projectNotFound }
            return (try Self.usedTime(db, projectId: projectId, now: now), project.budgetInterval)
        }
    }

    // MARK: Einträge

    /// Alle Einträge, die sich mit dem Intervall überschneiden (laufende eingeschlossen),
    /// nach Start sortiert.
    public func entries(in interval: DateInterval) throws -> [TimeEntry] {
        try writer.read { db in try Self.entries(db, in: interval) }
    }

    /// Legt einen Eintrag manuell an.
    /// - Throws: `TaktError.endBeforeStart`, `.timerAlreadyRunning` (Eintrag ohne Ende, obwohl
    ///   schon einer läuft), `.projectNotFound`.
    public func addEntry(_ entry: TimeEntry) throws {
        try writer.write { db in
            try Self.validate(entry, db)
            try entry.insert(db)
        }
    }

    /// Aktualisiert einen bestehenden Eintrag (Validierung wie bei `addEntry`).
    /// - Throws: zusätzlich `TaktError.entryNotFound`.
    public func updateEntry(_ entry: TimeEntry) throws {
        try writer.write { db in
            guard try TimeEntry.exists(db, id: entry.id) else { throw TaktError.entryNotFound }
            try Self.validate(entry, db)
            try entry.update(db)
        }
    }

    /// Löscht den Eintrag; ein unbekannter Eintrag wird ignoriert.
    public func deleteEntry(id: UUID) throws {
        try writer.write { db in _ = try TimeEntry.deleteOne(db, id: id) }
    }

    // MARK: Auswertungen

    /// Summe der auf das Intervall zugeschnittenen Dauern; laufende Einträge zählen bis `now`.
    public func totalDuration(in interval: DateInterval, now: Date = .now) throws -> TimeInterval {
        try entries(in: interval).reduce(0) { $0 + Self.clippedDuration($1, to: interval, now: now) }
    }

    /// Zugeschnittene Dauern je Projekt (nur Projekte mit Einträgen im Intervall).
    public func totalsByProject(in interval: DateInterval, now: Date = .now) throws -> [UUID: TimeInterval] {
        try entries(in: interval).reduce(into: [:]) { totals, entry in
            totals[entry.projectId, default: 0] += Self.clippedDuration(entry, to: interval, now: now)
        }
    }

    /// Projektwechsel und längster Block im Intervall (siehe `FocusStats`).
    public func focusStats(in interval: DateInterval, now: Date = .now) throws -> FocusStats {
        Self.focusStats(for: try entries(in: interval), in: interval, now: now)
    }
}

// MARK: - Interne Bausteine (auf `Database`, damit mehrere Abfragen in einer Transaktion laufen)

extension AppDatabase {
    static func activeEntry(_ db: Database) throws -> TimeEntry? {
        try TimeEntry.filter(TimeEntry.Columns.endedAt == nil).fetchOne(db)
    }

    static func lastNextStep(_ db: Database, projectId: UUID) throws -> String? {
        try TimeEntry
            .filter(TimeEntry.Columns.projectId == projectId && TimeEntry.Columns.endedAt != nil)
            .order(TimeEntry.Columns.endedAt.desc)
            .fetchOne(db)?
            .nextStep
    }

    static func recentProjects(_ db: Database, limit: Int, now: Date) throws -> [Project] {
        guard limit > 0 else { return [] }
        return try Project.fetchAll(db, sql: """
            SELECT project.*
            FROM project
            LEFT JOIN (
                SELECT projectId, MAX(startedAt) AS lastStartedAt
                FROM timeEntry
                WHERE startedAt <= ?
                GROUP BY projectId
            ) AS usage ON usage.projectId = project.id
            WHERE project.isArchived = 0
            ORDER BY usage.lastStartedAt IS NULL, usage.lastStartedAt DESC, project.sortOrder, project.name
            LIMIT ?
            """, arguments: [now.databaseTime, limit])
    }

    static func plannedBlock(_ db: Database, now: Date) throws -> PlannedBlock? {
        try PlannedBlock
            .filter(PlannedBlock.Columns.startAt >= now.addingTimeInterval(-plannedBlockGrace).databaseTime)
            .order(PlannedBlock.Columns.startAt, PlannedBlock.Columns.createdAt.desc)
            .fetchOne(db)
    }

    /// Löscht geplante Blöcke des Projekts, die zu `now` fällig sind (Beginn ≤ now + 15 min).
    static func deleteDuePlannedBlocks(_ db: Database, projectId: UUID, now: Date) throws {
        try PlannedBlock
            .filter(PlannedBlock.Columns.projectId == projectId)
            .filter(PlannedBlock.Columns.startAt <= now.addingTimeInterval(plannedBlockLeadTime).databaseTime)
            .deleteAll(db)
    }

    /// Summe aller Einträge des Projekts; laufende zählen bis `now`, nie negativ.
    static func usedTime(_ db: Database, projectId: UUID, now: Date) throws -> TimeInterval {
        try Double.fetchOne(db, sql: """
            SELECT TOTAL(MAX(0, COALESCE(endedAt, ?) - startedAt))
            FROM timeEntry
            WHERE projectId = ?
            """, arguments: [now.databaseTime, projectId]) ?? 0
    }

    static func entries(_ db: Database, in interval: DateInterval) throws -> [TimeEntry] {
        let startedAt = TimeEntry.Columns.startedAt
        let endedAt = TimeEntry.Columns.endedAt
        return try TimeEntry
            .filter(startedAt < interval.end.databaseTime)
            .filter(endedAt == nil || endedAt > interval.start.databaseTime)
            .order(startedAt, TimeEntry.Columns.id)
            .fetchAll(db)
    }

    /// Dauer des Eintrags innerhalb des Intervalls; laufende Einträge enden bei `now`.
    static func clippedDuration(_ entry: TimeEntry, to interval: DateInterval, now: Date) -> TimeInterval {
        let range = clippedRange(entry, to: interval, now: now)
        return range.end.timeIntervalSince(range.start)
    }

    /// Auf das Intervall zugeschnittener Zeitraum des Eintrags (nie mit Ende vor Start).
    static func clippedRange(_ entry: TimeEntry, to interval: DateInterval, now: Date) -> (start: Date, end: Date) {
        let start = max(entry.startedAt, interval.start)
        let end = max(start, min(entry.endedAt ?? now, interval.end))
        return (start, end)
    }

    /// Erwartet Einträge nach Start sortiert.
    static func focusStats(for entries: [TimeEntry], in interval: DateInterval, now: Date) -> FocusStats {
        var switches = 0
        var longestBlock: TimeInterval = 0
        var block: (projectId: UUID, start: Date, end: Date)?

        for entry in entries {
            let range = clippedRange(entry, to: interval, now: now)
            if let current = block {
                if current.projectId != entry.projectId { switches += 1 }
                let gap = range.start.timeIntervalSince(current.end)
                if current.projectId == entry.projectId && gap <= FocusStats.mergeGap {
                    block?.end = max(current.end, range.end)
                    continue
                }
                longestBlock = max(longestBlock, current.end.timeIntervalSince(current.start))
            }
            block = (entry.projectId, range.start, range.end)
        }
        if let current = block {
            longestBlock = max(longestBlock, current.end.timeIntervalSince(current.start))
        }
        return FocusStats(switches: switches, longestBlock: longestBlock)
    }

    static func validate(_ entry: TimeEntry, _ db: Database) throws {
        if let endedAt = entry.endedAt, endedAt < entry.startedAt {
            throw TaktError.endBeforeStart
        }
        guard try Project.exists(db, id: entry.projectId) else { throw TaktError.projectNotFound }
        if entry.isRunning, let running = try activeEntry(db), running.id != entry.id {
            throw TaktError.timerAlreadyRunning
        }
    }

    static func normalizedNote(_ note: String?) -> String? {
        guard let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func setArchived(_ archived: Bool, id: UUID) throws {
        try writer.write { db in
            let count = try Project
                .filter(id: id)
                .updateAll(db, Project.Columns.isArchived.set(to: archived))
            if count == 0 { throw TaktError.projectNotFound }
        }
    }
}
