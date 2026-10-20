import Foundation
import GRDB

// Datenbasis der Aktivitäts-Erkennung (Migration v5): Regeln „App / Fenster / Repository → Projekt“
// und beobachtete Aktivität für Vorschläge. Das Beobachten selbst (NSWorkspace, Accessibility)
// bleibt in der App.

// MARK: - Regeln

/// Worauf eine Aktivitäts-Regel schaut.
public enum ActivityRuleKind: String, CaseIterable, Codable, Sendable {
    /// Bundle-ID der vordersten App, exakt (ohne Rücksicht auf Groß-/Kleinschreibung).
    case bundleID
    /// Fenstertitel enthält das Muster.
    case windowTitleContains
    /// Git-Repository liegt in diesem Ordner (gleich oder darunter).
    case repoPath

    /// Deutscher Name für die Oberfläche.
    public var title: String {
        switch self {
        case .bundleID: "App"
        case .windowTitleContains: "Fenstertitel enthält"
        case .repoPath: "Repository-Ordner"
        }
    }
}

/// Ordnet beobachtete Aktivität einem Projekt zu. Es gilt die erste passende Regel nach `sortOrder`.
public struct ActivityRule: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "activityRule"

    public var id: UUID
    public var kind: ActivityRuleKind
    /// Suchmuster, getrimmt und nie leer (siehe `addActivityRule`).
    public var pattern: String
    public var projectId: UUID
    /// Reihenfolge der Prüfung, aufsteigend.
    public var sortOrder: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: ActivityRuleKind,
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

    /// Passt die Regel? Bundle-ID exakt, Titel als Teiltext (beides ohne Rücksicht auf
    /// Groß-/Kleinschreibung und Akzente), Repository-Pfad gleich oder darunter – verglichen auf
    /// normalisierten Pfaden (`normalizedPath`).
    public func matches(bundleID: String?, windowTitle: String?, repoPath: String?) -> Bool {
        switch kind {
        case .bundleID:
            let needle = RuleText.fold(pattern)
            guard !needle.isEmpty, let bundleID else { return false }
            return RuleText.fold(bundleID) == needle
        case .windowTitleContains:
            let needle = RuleText.fold(pattern)
            guard !needle.isEmpty, let windowTitle else { return false }
            return RuleText.fold(windowTitle).contains(needle)
        case .repoPath:
            guard let base = Self.normalizedPath(pattern), let path = repoPath.flatMap(Self.normalizedPath) else {
                return false
            }
            if path == base { return true }
            return path.hasPrefix(base == "/" ? "/" : base + "/")
        }
    }

    /// Pfad für Vergleiche: getrimmt, `~` aufgelöst, `.`/`..` und doppelte bzw. abschließende `/`
    /// entfernt, klein geschrieben (macOS-Volumes unterscheiden standardmäßig nicht). Symlinks
    /// werden bewusst nicht aufgelöst (kein Dateizugriff). Leer → `nil`.
    public static func normalizedPath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var raw = trimmed
        if raw.hasPrefix("file://"), let url = URL(string: raw) { raw = url.path }
        let expanded = (raw as NSString).expandingTildeInPath
        let isAbsolute = expanded.hasPrefix("/")
        var parts: [Substring] = []
        for component in expanded.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(component)
            }
        }
        let joined = parts.joined(separator: "/")
        let result = isAbsolute ? "/" + joined : joined
        return result.isEmpty ? nil : result.lowercased()
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

// MARK: - Beobachtete Aktivität

/// Ein Zeitabschnitt mit derselben vordersten App (und demselben Fenster/Repository).
/// Wird höchstens 30 Tage aufbewahrt (`activitySampleRetention`).
public struct ActivitySample: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "activitySample"

    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var bundleID: String
    public var windowTitle: String?
    public var repoPath: String?
    /// Per Regel ermitteltes Projekt; `nil` = unbekannt (oder Projekt gelöscht).
    public var projectId: UUID?

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        bundleID: String,
        windowTitle: String? = nil,
        repoPath: String? = nil,
        projectId: UUID? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.repoPath = repoPath
        self.projectId = projectId
    }

    public var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let startedAt = Column(CodingKeys.startedAt)
        public static let endedAt = Column(CodingKeys.endedAt)
        public static let bundleID = Column(CodingKeys.bundleID)
        public static let windowTitle = Column(CodingKeys.windowTitle)
        public static let repoPath = Column(CodingKeys.repoPath)
        public static let projectId = Column(CodingKeys.projectId)
    }
}

// MARK: - Datumsspeicherung

extension ActivityRule {
    public static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .timeIntervalSinceReferenceDate
    }

    public static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .timeIntervalSinceReferenceDate
    }
}

extension ActivitySample {
    public static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .timeIntervalSinceReferenceDate
    }

    public static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .timeIntervalSinceReferenceDate
    }
}

// MARK: - Repository

extension AppDatabase {
    /// Aufbewahrungsdauer beobachteter Aktivität: 30 Tage.
    public static let activitySampleRetention: TimeInterval = 30 * 24 * 3600

    // MARK: Regeln

    /// Alle Aktivitäts-Regeln in Prüfreihenfolge; Regeln unbekannter Art werden übersprungen.
    public func activityRules() throws -> [ActivityRule] {
        try writer.read { db in try Self.activityRules(db) }
    }

    /// Hängt eine Regel hinten an. Das Muster wird getrimmt.
    /// - Throws: `TaktError.emptyPattern`, `.projectNotFound`.
    @discardableResult
    public func addActivityRule(kind: ActivityRuleKind, pattern: String, projectId: UUID, now: Date = .now) throws -> ActivityRule {
        let pattern = try RuleText.validPattern(pattern)
        return try writer.write { db in
            guard try Project.exists(db, id: projectId) else { throw TaktError.projectNotFound }
            let last = try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM activityRule") ?? -1
            let rule = ActivityRule(kind: kind, pattern: pattern, projectId: projectId, sortOrder: last + 1, createdAt: now)
            try rule.insert(db)
            return rule
        }
    }

    /// Speichert eine geänderte (oder neue) Regel; Muster wie bei `addActivityRule`.
    /// - Throws: `TaktError.emptyPattern`, `.projectNotFound`.
    public func saveActivityRule(_ rule: ActivityRule) throws {
        var rule = rule
        rule.pattern = try RuleText.validPattern(rule.pattern)
        try writer.write { db in
            guard try Project.exists(db, id: rule.projectId) else { throw TaktError.projectNotFound }
            try rule.save(db)
        }
    }

    /// Löscht die Regel; eine unbekannte wird ignoriert.
    public func deleteActivityRule(id: UUID) throws {
        try writer.write { db in _ = try ActivityRule.deleteOne(db, id: id) }
    }

    /// Setzt `sortOrder` gemäß der Position in `ids`; nicht aufgeführte bleiben unverändert.
    public func reorderActivityRules(ids: [UUID]) throws {
        try writer.write { db in
            for (index, id) in ids.enumerated() {
                try ActivityRule.filter(id: id).updateAll(db, ActivityRule.Columns.sortOrder.set(to: index))
            }
        }
    }

    /// Projekt der ersten passenden Regel (nach `sortOrder`), sofern es nicht archiviert ist;
    /// Regeln archivierter Projekte werden übersprungen. Siehe `ActivityRule.matches`.
    public func matchActivityRule(bundleID: String?, windowTitle: String?, repoPath: String?) throws -> Project? {
        try writer.read { db in
            try Self.matchActivityRule(db, bundleID: bundleID, windowTitle: windowTitle, repoPath: repoPath)
        }
    }

    static func activityRules(_ db: Database) throws -> [ActivityRule] {
        try Row.fetchAll(db, sql: "SELECT * FROM activityRule ORDER BY sortOrder, createdAt, id")
            .compactMap { try? ActivityRule(row: $0) }
    }

    static func matchActivityRule(_ db: Database, bundleID: String?, windowTitle: String?, repoPath: String?) throws -> Project? {
        for rule in try activityRules(db)
        where rule.matches(bundleID: bundleID, windowTitle: windowTitle, repoPath: repoPath) {
            if let project = try Project.fetchOne(db, id: rule.projectId), !project.isArchived {
                return project
            }
        }
        return nil
    }

    // MARK: Beobachtete Aktivität

    /// Speichert einen Abschnitt beobachteter Aktivität. Texte werden getrimmt (leer → `nil`).
    /// Ohne `projectId` und mit `resolveProject` wird das Projekt per Regel ermittelt. In derselben
    /// Transaktion fallen Abschnitte weg, die mehr als 30 Tage vor diesem enden.
    /// - Throws: `TaktError.endBeforeStart`.
    @discardableResult
    public func addActivitySample(_ sample: ActivitySample, resolveProject: Bool = true) throws -> ActivitySample {
        guard sample.endedAt >= sample.startedAt else { throw TaktError.endBeforeStart }
        var sample = sample
        sample.bundleID = sample.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        sample.windowTitle = Self.normalizedNote(sample.windowTitle)
        sample.repoPath = Self.normalizedNote(sample.repoPath)
        return try writer.write { db in
            if sample.projectId == nil, resolveProject {
                sample.projectId = try Self.matchActivityRule(
                    db, bundleID: sample.bundleID, windowTitle: sample.windowTitle, repoPath: sample.repoPath
                )?.id
            } else if let projectId = sample.projectId, try !Project.exists(db, id: projectId) {
                sample.projectId = nil
            }
            try sample.insert(db)
            try Self.pruneActivitySamples(db, olderThan: sample.endedAt.addingTimeInterval(-Self.activitySampleRetention))
            return sample
        }
    }

    /// Abschnitte, die sich mit dem Intervall überschneiden, nach Beginn sortiert.
    public func activitySamples(in interval: DateInterval) throws -> [ActivitySample] {
        try writer.read { db in
            try ActivitySample
                .filter(ActivitySample.Columns.startedAt < interval.end.databaseTime)
                .filter(ActivitySample.Columns.endedAt > interval.start.databaseTime)
                .order(ActivitySample.Columns.startedAt, ActivitySample.Columns.id)
                .fetchAll(db)
        }
    }

    /// Löscht alle Abschnitte, die vor `date` enden. Gibt die Anzahl zurück.
    @discardableResult
    public func pruneActivitySamples(olderThan date: Date) throws -> Int {
        try writer.write { db in try Self.pruneActivitySamples(db, olderThan: date) }
    }

    @discardableResult
    static func pruneActivitySamples(_ db: Database, olderThan date: Date) throws -> Int {
        try ActivitySample.filter(ActivitySample.Columns.endedAt < date.databaseTime).deleteAll(db)
    }
}
