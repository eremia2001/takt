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

    private static var migrator: DatabaseMigrator {
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

        return migrator
    }
}
