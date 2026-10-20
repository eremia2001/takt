import Foundation
import GRDB

// Datenbasis der Kalender-Anbindung (Migration v5): gespiegelte Ereignisse je Eintrag und Regeln,
// die Kalenderereignisse einem Projekt zuordnen. EventKit selbst bleibt in der App; hier liegen
// nur Kennungen und reine Logik.

// MARK: - Verknüpfung Eintrag ↔ Kalenderereignis

/// Ein in den Kalender gespiegelter Zeiteintrag: Kennungen des EventKit-Ereignisses.
/// Höchstens eine Verknüpfung je Eintrag; wird der Eintrag gelöscht, verschwindet sie mit
/// (`ON DELETE CASCADE`) – das Ereignis im Kalender muss die App vorher selbst entfernen.
public struct CalendarEventLink: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "calendarEventLink"

    public var entryId: UUID
    /// `EKEvent.eventIdentifier`.
    public var eventIdentifier: String
    /// `EKCalendar.calendarIdentifier` des Zielkalenders.
    public var calendarIdentifier: String
    /// Zeitpunkt der letzten Spiegelung. Ist der Eintrag danach geändert worden
    /// (`TimeEntry.updatedAt` > `updatedAt`), muss neu gespiegelt werden.
    public var updatedAt: Date

    public var id: UUID { entryId }

    public init(entryId: UUID, eventIdentifier: String, calendarIdentifier: String, updatedAt: Date = .now) {
        self.entryId = entryId
        self.eventIdentifier = eventIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.updatedAt = updatedAt
    }

    public enum Columns {
        public static let entryId = Column(CodingKeys.entryId)
        public static let eventIdentifier = Column(CodingKeys.eventIdentifier)
        public static let calendarIdentifier = Column(CodingKeys.calendarIdentifier)
        public static let updatedAt = Column(CodingKeys.updatedAt)
    }
}

// MARK: - Kalender-Regeln

/// Worauf eine Kalender-Regel schaut.
public enum CalendarRuleKind: String, CaseIterable, Codable, Sendable {
    /// Name des Kalenders, exakt (ohne Rücksicht auf Groß-/Kleinschreibung).
    case calendarName
    /// Titel des Ereignisses enthält das Muster.
    case titleContains
    /// Ein Teilnehmer hat eine E-Mail-Adresse dieser Domain (Subdomains eingeschlossen).
    case attendeeDomain

    /// Deutscher Name für die Oberfläche.
    public var title: String {
        switch self {
        case .calendarName: "Kalender"
        case .titleContains: "Titel enthält"
        case .attendeeDomain: "Teilnehmer-Domain"
        }
    }
}

/// Ordnet Kalenderereignisse einem Projekt zu. Es gilt die erste passende Regel nach `sortOrder`.
public struct CalendarRule: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "calendarRule"

    public var id: UUID
    public var kind: CalendarRuleKind
    /// Suchmuster, getrimmt und nie leer (siehe `addCalendarRule`).
    public var pattern: String
    public var projectId: UUID
    /// Reihenfolge der Prüfung, aufsteigend.
    public var sortOrder: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: CalendarRuleKind,
        pattern: String,
        projectId: UUID,
        sortOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.pattern = pattern
        self.projectId = projectId
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    /// Passt die Regel auf das Ereignis? Vergleiche ohne Rücksicht auf Groß-/Kleinschreibung und
    /// Akzente. `attendeeDomains` dürfen Domains („acme.de“) oder ganze Adressen sein.
    public func matches(calendarName: String?, title: String?, attendeeDomains: [String]) -> Bool {
        let needle = RuleText.fold(pattern)
        guard !needle.isEmpty else { return false }
        switch kind {
        case .calendarName:
            guard let calendarName else { return false }
            return RuleText.fold(calendarName) == needle
        case .titleContains:
            guard let title else { return false }
            return RuleText.fold(title).contains(needle)
        case .attendeeDomain:
            guard let wanted = RuleText.domain(pattern) else { return false }
            return attendeeDomains.contains { candidate in
                guard let domain = RuleText.domain(candidate) else { return false }
                return domain == wanted || domain.hasSuffix("." + wanted)
            }
        }
    }

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let kind = Column(CodingKeys.kind)
        public static let pattern = Column(CodingKeys.pattern)
        public static let projectId = Column(CodingKeys.projectId)
        public static let sortOrder = Column(CodingKeys.sortOrder)
        public static let createdAt = Column(CodingKeys.createdAt)
    }
}

// MARK: - Textvergleich für Regeln

enum RuleText {
    /// Getrimmt, klein, ohne Akzente.
    static func fold(_ text: String) -> String {
        AppDatabase.foldedForSearch(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Domain aus „acme.de“, „@acme.de“ oder „anna@acme.de“, klein, ohne Punkt am Ende;
    /// leer → `nil`.
    static func domain(_ text: String) -> String? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("mailto:") { value.removeFirst("mailto:".count) }
        if let at = value.lastIndex(of: "@") { value = String(value[value.index(after: at)...]) }
        while value.hasSuffix(".") { value.removeLast() }
        while value.hasPrefix(".") { value.removeFirst() }
        return value.isEmpty ? nil : value
    }

    /// Muster für eine neue Regel: getrimmt, leer → Fehler.
    static func validPattern(_ pattern: String) throws -> String {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TaktError.emptyPattern }
        return trimmed
    }
}

// MARK: - Datumsspeicherung

extension CalendarEventLink {
    public static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .timeIntervalSinceReferenceDate
    }

    public static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .timeIntervalSinceReferenceDate
    }
}

extension CalendarRule {
    public static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .timeIntervalSinceReferenceDate
    }

    public static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .timeIntervalSinceReferenceDate
    }
}

// MARK: - Repository

extension AppDatabase {
    // MARK: Verknüpfungen

    /// Verknüpfung des Eintrags, falls er gespiegelt ist.
    public func calendarLink(entryId: UUID) throws -> CalendarEventLink? {
        try writer.read { db in try CalendarEventLink.fetchOne(db, key: entryId) }
    }

    /// Alle Verknüpfungen (z. B. zum Abgleich mit dem Kalender).
    public func calendarLinks() throws -> [CalendarEventLink] {
        try writer.read { db in try CalendarEventLink.order(CalendarEventLink.Columns.updatedAt).fetchAll(db) }
    }

    /// Legt die Verknüpfung an oder ersetzt die vorhandene des Eintrags.
    /// - Throws: `TaktError.entryNotFound`.
    public func setCalendarLink(_ link: CalendarEventLink) throws {
        try writer.write { db in
            guard try TimeEntry.exists(db, id: link.entryId) else { throw TaktError.entryNotFound }
            try link.save(db)
        }
    }

    /// Entfernt die Verknüpfung; ohne Verknüpfung passiert nichts.
    public func removeCalendarLink(entryId: UUID) throws {
        try writer.write { db in _ = try CalendarEventLink.deleteOne(db, key: entryId) }
    }

    /// Abgeschlossene Einträge, die (neu) in den Kalender gespiegelt werden müssen: Ende ab `since`,
    /// Dauer mindestens `minimumDuration`, und entweder ohne Verknüpfung oder nach der letzten
    /// Spiegelung geändert (`TimeEntry.updatedAt > link.updatedAt`). Nach Beginn sortiert.
    public func entriesNeedingMirror(since: Date, minimumDuration: TimeInterval) throws -> [TimeEntry] {
        try writer.read { db in
            try TimeEntry.fetchAll(db, sql: """
                SELECT timeEntry.*
                FROM timeEntry
                LEFT JOIN calendarEventLink AS link ON link.entryId = timeEntry.id
                WHERE timeEntry.endedAt IS NOT NULL
                  AND timeEntry.endedAt >= ?
                  AND timeEntry.endedAt - timeEntry.startedAt >= ?
                  AND (link.entryId IS NULL OR link.updatedAt < timeEntry.updatedAt)
                ORDER BY timeEntry.startedAt, timeEntry.id
                """, arguments: [since.databaseTime, max(0, minimumDuration)])
        }
    }

    /// Entfernt Verknüpfungen ohne (abgeschlossenen) Eintrag – etwa Altlasten aus Zeiten ohne
    /// Fremdschlüssel-Prüfung oder Einträge, die wieder laufen. Gibt die entfernten zurück, damit
    /// die App deren Ereignisse löschen kann.
    @discardableResult
    public func removeOrphanLinks() throws -> [CalendarEventLink] {
        try writer.write { db in
            let orphans = try CalendarEventLink.fetchAll(db, sql: """
                SELECT link.*
                FROM calendarEventLink AS link
                LEFT JOIN timeEntry ON timeEntry.id = link.entryId
                WHERE timeEntry.id IS NULL OR timeEntry.endedAt IS NULL
                """)
            for orphan in orphans { try orphan.delete(db) }
            return orphans
        }
    }

    // MARK: Regeln

    /// Alle Kalender-Regeln in Prüfreihenfolge. Regeln unbekannter Art (z. B. aus einer neueren
    /// App-Version) werden übersprungen statt das Lesen scheitern zu lassen.
    public func calendarRules() throws -> [CalendarRule] {
        try writer.read { db in try Self.calendarRules(db) }
    }

    /// Hängt eine Regel hinten an. Das Muster wird getrimmt.
    /// - Throws: `TaktError.emptyPattern`, `.projectNotFound`.
    @discardableResult
    public func addCalendarRule(kind: CalendarRuleKind, pattern: String, projectId: UUID, now: Date = .now) throws -> CalendarRule {
        let pattern = try RuleText.validPattern(pattern)
        return try writer.write { db in
            guard try Project.exists(db, id: projectId) else { throw TaktError.projectNotFound }
            let last = try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM calendarRule") ?? -1
            let rule = CalendarRule(kind: kind, pattern: pattern, projectId: projectId, sortOrder: last + 1, createdAt: now)
            try rule.insert(db)
            return rule
        }
    }

    /// Speichert eine geänderte (oder neue) Regel; Muster wie bei `addCalendarRule`.
    /// - Throws: `TaktError.emptyPattern`, `.projectNotFound`.
    public func saveCalendarRule(_ rule: CalendarRule) throws {
        var rule = rule
        rule.pattern = try RuleText.validPattern(rule.pattern)
        try writer.write { db in
            guard try Project.exists(db, id: rule.projectId) else { throw TaktError.projectNotFound }
            try rule.save(db)
        }
    }

    /// Löscht die Regel; eine unbekannte wird ignoriert.
    public func deleteCalendarRule(id: UUID) throws {
        try writer.write { db in _ = try CalendarRule.deleteOne(db, id: id) }
    }

    /// Setzt `sortOrder` gemäß der Position in `ids`; nicht aufgeführte bleiben unverändert.
    public func reorderCalendarRules(ids: [UUID]) throws {
        try writer.write { db in
            for (index, id) in ids.enumerated() {
                try CalendarRule.filter(id: id).updateAll(db, CalendarRule.Columns.sortOrder.set(to: index))
            }
        }
    }

    /// Projekt der ersten passenden Regel (nach `sortOrder`), sofern es nicht archiviert ist;
    /// Regeln archivierter Projekte werden übersprungen. Siehe `CalendarRule.matches`.
    public func matchCalendarRule(calendarName: String?, title: String?, attendeeDomains: [String] = []) throws -> Project? {
        try writer.read { db in
            for rule in try Self.calendarRules(db)
            where rule.matches(calendarName: calendarName, title: title, attendeeDomains: attendeeDomains) {
                if let project = try Project.fetchOne(db, id: rule.projectId), !project.isArchived {
                    return project
                }
            }
            return nil
        }
    }

    static func calendarRules(_ db: Database) throws -> [CalendarRule] {
        try Row.fetchAll(db, sql: "SELECT * FROM calendarRule ORDER BY sortOrder, createdAt, id")
            .compactMap { try? CalendarRule(row: $0) }
    }
}
