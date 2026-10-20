import Foundation
import GRDB

// MARK: - Projekt

/// Ein Projekt, auf das Zeit gebucht wird. Archivieren statt löschen.
public struct Project: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "project"

    public var id: UUID
    public var name: String
    /// Projektfarbe als `#RRGGBB`, siehe `ProjectPalette`.
    public var colorHex: String
    /// `true` = Business, `false` = Privat.
    public var isBusiness: Bool
    public var isArchived: Bool
    /// Manuelle Reihenfolge, aufsteigend.
    public var sortOrder: Int
    /// Optionale Musikquelle: beliebige URI oder URL, z. B. `spotify:playlist:…`,
    /// `https://music.youtube.com/playlist?list=…`, `https://music.apple.com/…` oder
    /// `applemusic:playlist:<Name>`. Die Auswertung ist Sache der Musiksteuerung.
    public var musicSource: String?
    /// Optionaler Kunde, freier Text.
    public var client: String?
    /// Stundensatz in der Währung aus den Einstellungen; `nil` = kein eigener Satz
    /// (dann gilt der Standard-Stundensatz, falls gesetzt). In SQLite als TEXT gespeichert.
    public var hourlyRate: Decimal?
    /// Zeit auf diesem Projekt ist abrechenbar (Vorgabe für alle Einträge, siehe
    /// `TimeEntry.isBillable`). Standard: wie `isBusiness`.
    public var isBillable: Bool
    /// Stundenbudget des Projekts in Stunden; `nil` = kein Budget. In SQLite als TEXT gespeichert
    /// (wie `hourlyRate`). Gezählt wird über alle Einträge des Projekts, siehe `budgetUsage`.
    public var budgetHours: Decimal?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        isBusiness: Bool = true,
        isArchived: Bool = false,
        sortOrder: Int = 0,
        musicSource: String? = nil,
        client: String? = nil,
        hourlyRate: Decimal? = nil,
        isBillable: Bool? = nil,
        budgetHours: Decimal? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isBusiness = isBusiness
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.musicSource = musicSource
        self.client = client
        self.hourlyRate = hourlyRate
        self.isBillable = isBillable ?? isBusiness
        self.budgetHours = budgetHours
        self.createdAt = createdAt
    }

    /// Alte Initialisierung mit `playlistURI` (vor v2). Nur für bestehenden Code.
    @available(*, deprecated, message: "Durch musicSource ersetzt")
    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        isBusiness: Bool = true,
        isArchived: Bool = false,
        sortOrder: Int = 0,
        playlistURI: String?,
        createdAt: Date = .now
    ) {
        self.init(
            id: id, name: name, colorHex: colorHex, isBusiness: isBusiness, isArchived: isArchived,
            sortOrder: sortOrder, musicSource: playlistURI, createdAt: createdAt
        )
    }

    /// Veralteter Alias für `musicSource` (vor v2 nur Spotify-Playlists).
    /// Kein gespeichertes Feld – die alte Spalte `playlistURI` wird nicht mehr gelesen oder geschrieben.
    @available(*, deprecated, renamed: "musicSource")
    public var playlistURI: String? {
        get { musicSource }
        set { musicSource = newValue }
    }

    /// Gespeicherte Felder. Ausdrücklich aufgeführt, damit der Alias `playlistURI` nie mitkodiert wird.
    public enum CodingKeys: String, CodingKey {
        case id, name, colorHex, isBusiness, isArchived, sortOrder
        case musicSource, client, hourlyRate, isBillable, budgetHours, createdAt
    }

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let name = Column(CodingKeys.name)
        public static let isArchived = Column(CodingKeys.isArchived)
        public static let sortOrder = Column(CodingKeys.sortOrder)
        public static let isBusiness = Column(CodingKeys.isBusiness)
        public static let isBillable = Column(CodingKeys.isBillable)
        public static let client = Column(CodingKeys.client)
        public static let hourlyRate = Column(CodingKeys.hourlyRate)
        public static let musicSource = Column(CodingKeys.musicSource)
        public static let budgetHours = Column(CodingKeys.budgetHours)
    }

    /// Budget in Sekunden; `nil` ohne Budget (oder bei einem Budget ≤ 0).
    public var budgetInterval: TimeInterval? {
        guard let budgetHours, budgetHours > 0 else { return nil }
        return NSDecimalNumber(decimal: budgetHours * 3600).doubleValue
    }
}

// MARK: - Zeiteintrag

/// Ein Zeitabschnitt auf einem Projekt. `endedAt == nil` heißt: läuft gerade.
public struct TimeEntry: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "timeEntry"

    public var id: UUID
    public var projectId: UUID
    public var startedAt: Date
    public var endedAt: Date?
    /// Notiz „Nächster Schritt“, beim Stoppen erfasst.
    public var nextStep: String?
    /// Abrechenbar abweichend vom Projekt; `nil` = vom Projekt erben.
    public var isBillable: Bool?

    public init(
        id: UUID = UUID(),
        projectId: UUID,
        startedAt: Date,
        endedAt: Date? = nil,
        nextStep: String? = nil,
        isBillable: Bool? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.nextStep = nextStep
        self.isBillable = isBillable
    }

    public var isRunning: Bool { endedAt == nil }

    /// Abrechenbarkeit des Eintrags: eigener Wert, sonst der des Projekts.
    public func effectiveBillable(project: Project) -> Bool {
        isBillable ?? project.isBillable
    }

    /// Dauer bis `endedAt` bzw. – falls laufend – bis `now`. Nie negativ.
    public func duration(at now: Date = .now) -> TimeInterval {
        max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let projectId = Column(CodingKeys.projectId)
        public static let startedAt = Column(CodingKeys.startedAt)
        public static let endedAt = Column(CodingKeys.endedAt)
        public static let nextStep = Column(CodingKeys.nextStep)
        public static let isBillable = Column(CodingKeys.isBillable)
    }
}

// MARK: - Geplanter Block

/// Der „nächste Block“: ein für später geplanter Start eines Projekts. Es gibt höchstens einen;
/// `setPlannedBlock` ersetzt alle vorhandenen, abgelaufene werden beim Lesen ignoriert.
public struct PlannedBlock: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "plannedBlock"

    public var id: UUID
    public var projectId: UUID
    /// Geplanter Beginn.
    public var startAt: Date
    /// Optionale Notiz, z. B. was in dem Block passieren soll.
    public var note: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        projectId: UUID,
        startAt: Date,
        note: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.projectId = projectId
        self.startAt = startAt
        self.note = note
        self.createdAt = createdAt
    }

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let projectId = Column(CodingKeys.projectId)
        public static let startAt = Column(CodingKeys.startAt)
        public static let note = Column(CodingKeys.note)
        public static let createdAt = Column(CodingKeys.createdAt)
    }
}

// MARK: - Datumsspeicherung

// Datumswerte werden als REAL (Sekunden seit 2001-01-01, wie `Date` intern) gespeichert.
// Vorteil gegenüber GRDBs Standard (Text mit Millisekunden): verlustfreier Rundweg –
// ein gespeicherter Eintrag ist nach dem Lesen wieder `==` zum Original – und
// Vergleiche in SQL sind rein numerisch.
// Wichtig: In eigenen SQL-Bedingungen Daten deshalb immer über `Date.databaseTime` binden.

extension Project {
    public static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .timeIntervalSinceReferenceDate
    }

    public static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .timeIntervalSinceReferenceDate
    }
}

extension TimeEntry {
    public static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .timeIntervalSinceReferenceDate
    }

    public static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .timeIntervalSinceReferenceDate
    }
}

extension PlannedBlock {
    public static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .timeIntervalSinceReferenceDate
    }

    public static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .timeIntervalSinceReferenceDate
    }
}

extension Date {
    /// Darstellung in der Datenbank (siehe oben), für SQL-Bedingungen.
    var databaseTime: Double { timeIntervalSinceReferenceDate }
}

// MARK: - Farbpalette

/// Ruhige, an Apples Systemfarben angelehnte Projektfarben.
public enum ProjectPalette {
    public static let colors: [String] = [
        "#007AFF", // Blau
        "#30B0C7", // Teal
        "#5856D6", // Indigo
        "#FF9500", // Orange
        "#FF2D55", // Pink
        "#34C759", // Grün
        "#8E8E93", // Grau
        "#A2845E", // Braun
    ]

    /// Erste noch nicht genutzte Farbe (Groß-/Kleinschreibung egal);
    /// sind alle vergeben, geht es zyklisch anhand der Anzahl genutzter Farben weiter.
    public static func next(after used: [String]) -> String {
        let usedSet = Set(used.map { $0.uppercased() })
        if let free = colors.first(where: { !usedSet.contains($0.uppercased()) }) {
            return free
        }
        return colors[used.count % colors.count]
    }
}

// MARK: - Fehler

public enum TaktError: Error, Equatable, Sendable, LocalizedError {
    /// Ende liegt vor dem Start.
    case endBeforeStart
    /// Es läuft bereits ein Eintrag; ein zweiter laufender ist nicht erlaubt.
    case timerAlreadyRunning
    case entryNotFound
    case projectNotFound

    public var errorDescription: String? {
        switch self {
        case .endBeforeStart: "Das Ende darf nicht vor dem Start liegen."
        case .timerAlreadyRunning: "Es läuft bereits ein Timer."
        case .entryNotFound: "Der Eintrag existiert nicht."
        case .projectNotFound: "Das Projekt existiert nicht."
        }
    }
}
