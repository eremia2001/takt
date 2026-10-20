import Foundation
import GRDB
import Testing
@testable import TaktCore

@Suite("Migration v1 → v2")
struct MigrationTests {
    /// Baut eine v1-Datenbank mit Rohdaten auf (Schema wie vor v2), ohne die heutigen Modelle.
    private func makeV1Database() throws -> (DatabaseQueue, business: UUID, personal: UUID, entry: UUID) {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v1")
        let business = UUID()
        let personal = UUID()
        let entry = UUID()
        try queue.write { db in
            #expect(try !db.columns(in: "project").map(\.name).contains("musicSource"))
            try db.execute(sql: """
                INSERT INTO project (id, name, colorHex, isBusiness, isArchived, sortOrder, playlistURI, createdAt)
                VALUES (?, 'Kundenportal', '#007AFF', 1, 0, 0, 'spotify:playlist:abc', ?),
                       (?, 'Garten', '#34C759', 0, 1, 1, NULL, ?)
                """, arguments: [business, date(2026, 1, 1).databaseTime, personal, date(2026, 2, 1).databaseTime])
            try db.execute(sql: """
                INSERT INTO timeEntry (id, projectId, startedAt, endedAt, nextStep)
                VALUES (?, ?, ?, ?, 'Tests schreiben'),
                       (?, ?, ?, NULL, NULL)
                """, arguments: [
                    entry, business, date(2026, 10, 19, 9).databaseTime, date(2026, 10, 19, 11).databaseTime,
                    UUID(), personal, date(2026, 10, 20, 8).databaseTime,
                ])
        }
        return (queue, business, personal, entry)
    }

    @Test("Bestehende Daten bleiben erhalten, neue Spalten bekommen sinnvolle Werte")
    func migratesData() throws {
        let (queue, businessId, personalId, entryId) = try makeV1Database()
        let db = try AppDatabase(queue)  // führt v2 aus

        let projects = try db.allProjects()
        #expect(projects.count == 2)
        let business = try #require(projects.first { $0.id == businessId })
        #expect(business.name == "Kundenportal")
        #expect(business.colorHex == "#007AFF")
        #expect(business.isBusiness)
        #expect(!business.isArchived)
        #expect(business.createdAt == date(2026, 1, 1))
        #expect(business.musicSource == "spotify:playlist:abc")
        #expect(business.isBillable)              // erbt isBusiness
        #expect(business.hourlyRate == nil)
        #expect(business.client == nil)

        let personal = try #require(projects.first { $0.id == personalId })
        #expect(personal.isArchived)
        #expect(!personal.isBillable)
        #expect(personal.musicSource == nil)

        let entries = try db.entries(in: DateInterval(start: date(2026, 10, 1), end: date(2026, 11, 1)))
        #expect(entries.count == 2)
        let finished = try #require(entries.first { $0.id == entryId })
        #expect(finished.startedAt == date(2026, 10, 19, 9))
        #expect(finished.endedAt == date(2026, 10, 19, 11))
        #expect(finished.nextStep == "Tests schreiben")
        #expect(finished.isBillable == nil)
        #expect(try db.activeEntry()?.projectId == personalId)
        #expect(try db.lastNextStep(projectId: businessId) == "Tests schreiben")
    }

    @Test("Schema v2: neue Spalten, alte playlistURI-Spalte bleibt, Migration ist idempotent")
    func schema() throws {
        let (queue, _, _, _) = try makeV1Database()
        _ = try AppDatabase(queue)
        _ = try AppDatabase(queue)  // zweites Öffnen: nichts passiert
        try queue.read { db in
            let projectColumns = Set(try db.columns(in: "project").map(\.name))
            #expect(projectColumns.isSuperset(of: ["hourlyRate", "isBillable", "client", "musicSource", "playlistURI"]))
            #expect(try db.columns(in: "timeEntry").map(\.name).contains("isBillable"))
            #expect(try AppDatabase.migrator.appliedIdentifiers(db) == ["v1", "v2", "v3"])
        }
    }

    @Test("Decimal wird als Text gespeichert und verlustfrei gelesen")
    func decimalRoundTrip() throws {
        let db = try AppDatabase.inMemory()
        let project = Project(
            name: "Beratung", colorHex: "#007AFF", client: "ACME GmbH",
            hourlyRate: Decimal(string: "92.35")!, isBillable: true
        )
        try db.saveProject(project)
        #expect(try db.project(id: project.id) == project)
        let stored = try db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT hourlyRate FROM project WHERE id = ?", arguments: [project.id])
        }
        #expect(stored == "92.35")
        let type = try db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT typeof(hourlyRate) FROM project WHERE id = ?", arguments: [project.id])
        }
        #expect(type == "text")
    }

    @Test("Abrechenbar: Projekt-Standard folgt Business, Eintrag kann abweichen")
    func billableDefaults() throws {
        let business = Project(name: "B", colorHex: "#007AFF", isBusiness: true)
        let personal = Project(name: "P", colorHex: "#007AFF", isBusiness: false)
        #expect(business.isBillable)
        #expect(!personal.isBillable)
        #expect(Project(name: "X", colorHex: "#007AFF", isBusiness: true, isBillable: false).isBillable == false)

        var entry = TimeEntry(projectId: business.id, startedAt: date(2026, 10, 20, 9))
        #expect(entry.effectiveBillable(project: business))
        #expect(!entry.effectiveBillable(project: personal))
        entry.isBillable = false
        #expect(!entry.effectiveBillable(project: business))
        entry.isBillable = true
        #expect(entry.effectiveBillable(project: personal))
    }

    @Test("Eintrag mit eigenem isBillable wird gespeichert")
    func entryBillableRoundTrip() throws {
        let f = try Fixture()
        let entry = TimeEntry(projectId: f.alpha.id, startedAt: date(2026, 10, 20, 9), endedAt: date(2026, 10, 20, 10), isBillable: false)
        try f.db.addEntry(entry)
        #expect(try f.db.entries(in: DateInterval(start: date(2026, 10, 20), end: date(2026, 10, 21))) == [entry])
    }

    @Test("playlistURI ist ein Alias für musicSource")
    @available(*, deprecated)
    func playlistAlias() {
        var project = Project(name: "X", colorHex: "#007AFF", playlistURI: "spotify:playlist:1")
        #expect(project.musicSource == "spotify:playlist:1")
        project.playlistURI = "applemusic:playlist:Fokus"
        #expect(project.musicSource == "applemusic:playlist:Fokus")
    }
}
