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
    /// Optionale Spotify-Playlist (z. B. `spotify:playlist:…`).
    public var playlistURI: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        isBusiness: Bool = true,
        isArchived: Bool = false,
        sortOrder: Int = 0,
        playlistURI: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isBusiness = isBusiness
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.playlistURI = playlistURI
        self.createdAt = createdAt
    }

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let name = Column(CodingKeys.name)
        public static let isArchived = Column(CodingKeys.isArchived)
        public static let sortOrder = Column(CodingKeys.sortOrder)
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

    public init(
        id: UUID = UUID(),
        projectId: UUID,
        startedAt: Date,
        endedAt: Date? = nil,
        nextStep: String? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.nextStep = nextStep
    }

    public var isRunning: Bool { endedAt == nil }

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
