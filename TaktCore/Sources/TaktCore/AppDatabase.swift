import Foundation
import GRDB

/// Zugang zur SQLite-Datenbank. Wird von App und Widget-Extension gemeinsam genutzt
/// (Datei im App-Group-Container).
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    /// Übernimmt einen fertigen Writer und führt alle Migrationen aus.
    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    // MARK: Fabriken

    /// Flüchtige Datenbank für Tests und Vorschauen.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: makeConfiguration()))
    }

    /// Datenbank auf der Platte; legt fehlende Ordner an.
    public static func onDisk(at url: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let pool = try DatabasePool(path: url.path, configuration: makeConfiguration())
        return try AppDatabase(pool)
    }

    // Team-Präfix-Form: unter macOS ohne Freischaltung im Developer-Portal nutzbar.
    public static let appGroupID = "N5GJ4D394X.group.dev.eremiya.takt"

    /// `takt.sqlite` im App-Group-Container; ohne Container (z. B. fehlendes Entitlement)
    /// Fallback nach `~/Library/Application Support/Takt/`.
    public static func defaultURL() -> URL {
        let fileName = "takt.sqlite"
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return container.appendingPathComponent(fileName)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("Takt", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// Gemeinsame Instanz für App und Widget (statische Konstanten sind in Swift lazy).
    public static let shared: AppDatabase = {
        let url = defaultURL()
        do {
            return try onDisk(at: url)
        } catch {
            fatalError("Takt: Datenbank unter \(url.path) konnte nicht geöffnet werden: \(error)")
        }
    }()

    // MARK: Konfiguration & Migrationen

    private static func makeConfiguration() -> Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        // App und Widget greifen parallel zu: kurz warten statt sofort SQLITE_BUSY.
        config.busyMode = .timeout(5)
        return config
    }

    /// Alle Migrationen. `internal`, damit Tests ältere Stände aufbauen können
    /// (`migrator.migrate(writer, upTo: "v1")`, … `"v4"`).
    static var migrator: DatabaseMigrator {
        // Bewusst ohne `eraseDatabaseOnSchemaChange`: echte Zeitdaten nie automatisch löschen.
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "project") { t in
                t.primaryKey("id", .blob)
                t.column("name", .text).notNull()
                t.column("colorHex", .text).notNull()
                t.column("isBusiness", .boolean).notNull().defaults(to: true)
                t.column("isArchived", .boolean).notNull().defaults(to: false)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("playlistURI", .text)
                t.column("createdAt", .double).notNull()  // Sekunden seit 2001, siehe Models.swift
            }

            try db.create(table: "timeEntry") { t in
                t.primaryKey("id", .blob)
                t.column("projectId", .blob)
                    .notNull()
                    .indexed()
                    .references("project", column: "id", onDelete: .restrict)
                t.column("startedAt", .double).notNull().indexed()
                t.column("endedAt", .double).indexed()
                t.column("nextStep", .text)
            }

            // Absicherung auf Datenbankebene: höchstens ein laufender Eintrag.
            // (NULL-Werte gelten in UNIQUE-Indizes als verschieden, daher der Ausdruck.)
            try db.execute(sql: """
                CREATE UNIQUE INDEX timeEntry_singleRunning
                ON timeEntry((endedAt IS NULL))
                WHERE endedAt IS NULL
                """)
        }

        // v2: Abrechnung (Stundensatz, Kunde, abrechenbar) und allgemeine Musikquelle.
        migrator.registerMigration("v2") { db in
            try db.alter(table: "project") { t in
                // Decimal als TEXT in POSIX-Schreibweise („85.5“): verlustfrei, GRDB liest und
                // schreibt `Decimal` nativ so. NULL = kein eigener Satz.
                t.add(column: "hourlyRate", .text)
                t.add(column: "isBillable", .boolean).notNull().defaults(to: false)
                t.add(column: "client", .text)
                t.add(column: "musicSource", .text)
                // Die alte Spalte `playlistURI` bleibt als Altbestand stehen (Rückweg zu v1 ohne
                // Datenverlust), wird aber nicht mehr geschrieben.
            }
            try db.execute(sql: "UPDATE project SET isBillable = isBusiness, musicSource = playlistURI")

            try db.alter(table: "timeEntry") { t in
                // NULL = Abrechenbarkeit vom Projekt erben.
                t.add(column: "isBillable", .boolean)
            }
        }

        // v3: Stundenbudget je Projekt und der geplante „nächste Block“ (Widget v2).
        migrator.registerMigration("v3") { db in
            try db.alter(table: "project") { t in
                // Stunden als TEXT in POSIX-Schreibweise wie `hourlyRate`; NULL = kein Budget.
                t.add(column: "budgetHours", .text)
            }
            try db.create(table: "plannedBlock") { t in
                t.primaryKey("id", .blob)
                t.column("projectId", .blob)
                    .notNull()
                    .indexed()
                    .references("project", column: "id", onDelete: .cascade)
                t.column("startAt", .double).notNull().indexed()  // Sekunden seit 2001
                t.column("note", .text)
                t.column("createdAt", .double).notNull()
            }
        }

        // v4: Tag je Eintrag und freie Tage (Urlaub, Krank, Feiertag, Sonstiges).
        migrator.registerMigration("v4") { db in
            try db.alter(table: "timeEntry") { t in
                // NULL = ohne Tag.
                t.add(column: "tag", .text)
            }
            // Für die Tag-Vorschläge (zuletzt genutzte Tags je Projekt).
            try db.execute(sql: """
                CREATE INDEX timeEntry_tag ON timeEntry(tag, projectId, startedAt)
                WHERE tag IS NOT NULL
                """)
            try db.create(table: "dayOff") { t in
                t.primaryKey("id", .blob)
                // Kalendertag als Text `YYYY-MM-DD`: unabhängig von Zeitzone und Uhrzeit.
                t.column("date", .text).notNull().unique()
                t.column("kind", .text).notNull()  // Rohwert von `DayOffKind`
                t.column("note", .text)
            }
        }

        // v5: Datenbasis für Kalender-Anbindung und Aktivitäts-Erkennung.
        migrator.registerMigration("v5") { db in
            // Letzte Änderung je Eintrag (für die Kalender-Spiegelung). Altbestände: Beginn.
            try db.alter(table: "timeEntry") { t in
                t.add(column: "updatedAt", .double).notNull().defaults(to: 0)
            }
            try db.execute(sql: "UPDATE timeEntry SET updatedAt = startedAt")

            // Gespiegeltes Kalenderereignis je Eintrag (EventKit-Kennungen).
            try db.create(table: "calendarEventLink") { t in
                t.primaryKey("entryId", .blob)
                    .references("timeEntry", column: "id", onDelete: .cascade)
                t.column("eventIdentifier", .text).notNull()
                t.column("calendarIdentifier", .text).notNull()
                t.column("updatedAt", .double).notNull()
            }

            // Regeln Kalenderereignis → Projekt.
            try db.create(table: "calendarRule") { t in
                t.primaryKey("id", .blob)
                t.column("kind", .text).notNull()  // Rohwert von `CalendarRuleKind`
                t.column("pattern", .text).notNull()
                t.column("projectId", .blob)
                    .notNull()
                    .indexed()
                    .references("project", column: "id", onDelete: .cascade)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .double).notNull()
            }

            // Regeln App/Fenster/Repository → Projekt.
            try db.create(table: "activityRule") { t in
                t.primaryKey("id", .blob)
                t.column("kind", .text).notNull()  // Rohwert von `ActivityRuleKind`
                t.column("pattern", .text).notNull()
                t.column("projectId", .blob)
                    .notNull()
                    .indexed()
                    .references("project", column: "id", onDelete: .cascade)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .double).notNull()
            }

            // Beobachtete Aktivität (höchstens 30 Tage), Grundlage für Vorschläge.
            try db.create(table: "activitySample") { t in
                t.primaryKey("id", .blob)
                t.column("startedAt", .double).notNull().indexed()
                t.column("endedAt", .double).notNull().indexed()
                t.column("bundleID", .text).notNull()
                t.column("windowTitle", .text)
                t.column("repoPath", .text)
                // Ein gelöschtes Projekt macht die Probe nur „unbekannt“.
                t.column("projectId", .blob)
                    .indexed()
                    .references("project", column: "id", onDelete: .setNull)
            }
        }

        return migrator
    }
}
