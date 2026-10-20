import Foundation
import GRDB
import Testing
@testable import TaktCore

@Suite("Datenbank und Projekte")
struct DatabaseTests {
    @Test("Migration legt Tabellen, Fremdschlüssel und Indizes an")
    func migration() throws {
        let db = try AppDatabase.inMemory()
        try db.writer.read { db in
            #expect(try db.tableExists("project"))
            #expect(try db.tableExists("timeEntry"))
            let foreignKeys = try db.foreignKeys(on: "timeEntry")
            #expect(foreignKeys.count == 1)
            #expect(foreignKeys.first?.destinationTable == "project")
            let indexedColumns = try db.indexes(on: "timeEntry").map(\.columns)
            #expect(indexedColumns.contains(["startedAt"]))
            #expect(indexedColumns.contains(["endedAt"]))
        }
    }

    @Test("Projekt mit laufenden Einträgen lässt sich nicht löschen (restrict)")
    func foreignKeyRestrict() throws {
        let f = try Fixture()
        try f.entry(f.alpha, date(2026, 10, 20, 9), date(2026, 10, 20, 10))
        #expect(throws: DatabaseError.self) {
            try f.db.writer.write { db in _ = try Project.deleteOne(db, id: f.alpha.id) }
        }
    }

    @Test("Eindeutiger Teilindex verhindert zwei laufende Einträge auch an der Validierung vorbei")
    func singleRunningIndex() throws {
        let f = try Fixture()
        try f.db.writer.write { db in
            try TimeEntry(projectId: f.alpha.id, startedAt: date(2026, 10, 20, 9)).insert(db)
            // Abgeschlossene Einträge sind beliebig viele erlaubt
            try TimeEntry(projectId: f.beta.id, startedAt: date(2026, 10, 20, 7), endedAt: date(2026, 10, 20, 8)).insert(db)
            try TimeEntry(projectId: f.beta.id, startedAt: date(2026, 10, 20, 5), endedAt: date(2026, 10, 20, 6)).insert(db)
        }
        #expect(throws: DatabaseError.self) {
            try f.db.writer.write { db in
                try TimeEntry(projectId: f.beta.id, startedAt: date(2026, 10, 20, 10)).insert(db)
            }
        }
    }

    @Test("Datenbank auf der Platte: Ordner wird angelegt")
    func onDisk() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("takt-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("nested/takt.sqlite")
        let db = try AppDatabase.onDisk(at: url)
        try db.saveProject(Project(name: "X", colorHex: "#007AFF"))
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try db.allProjects().count == 1)
    }

    @Test("defaultURL endet auf takt.sqlite")
    func defaultURL() {
        #expect(AppDatabase.defaultURL().lastPathComponent == "takt.sqlite")
    }

    @Test("Projekt speichern: Insert, dann Update, Werte bleiben exakt erhalten")
    func saveProject() throws {
        let db = try AppDatabase.inMemory()
        var project = Project(name: "Kundenportal", colorHex: "#007AFF", playlistURI: "spotify:playlist:1")
        try db.saveProject(project)
        #expect(try db.project(id: project.id) == project)

        project.name = "Kundenportal v2"
        project.isBusiness = false
        try db.saveProject(project)
        #expect(try db.project(id: project.id) == project)
        #expect(try db.allProjects().count == 1)
        #expect(try db.project(id: UUID()) == nil)
    }

    @Test("Archivieren und Wiederherstellen")
    func archive() throws {
        let f = try Fixture()
        try f.db.archiveProject(id: f.beta.id)
        #expect(try f.db.activeProjects().map(\.name) == ["Alpha", "Gamma"])
        #expect(try f.db.allProjects().count == 3)
        #expect(try f.db.project(id: f.beta.id)?.isArchived == true)

        try f.db.unarchiveProject(id: f.beta.id)
        #expect(try f.db.activeProjects().map(\.name) == ["Alpha", "Beta", "Gamma"])
    }

    @Test("Reihenfolge setzen")
    func reorder() throws {
        let f = try Fixture()
        try f.db.reorderProjects(ids: [f.gamma.id, f.alpha.id, f.beta.id])
        #expect(try f.db.activeProjects().map(\.name) == ["Gamma", "Alpha", "Beta"])
        #expect(try f.db.allProjects().map(\.sortOrder) == [0, 1, 2])
    }
}

@Suite("Palette und Formatierung")
struct PaletteAndFormatTests {
    @Test("Palette hat 8 eindeutige Hex-Farben")
    func palette() {
        let colors = ProjectPalette.colors
        #expect(colors.count == 8)
        #expect(Set(colors.map { $0.uppercased() }).count == 8)
        for color in colors {
            #expect(color.hasPrefix("#") && color.count == 7)
        }
    }

    @Test("Nächste freie Farbe, sonst zyklisch")
    func paletteNext() {
        let colors = ProjectPalette.colors
        #expect(ProjectPalette.next(after: []) == colors[0])
        #expect(ProjectPalette.next(after: [colors[0], colors[1]]) == colors[2])
        #expect(ProjectPalette.next(after: [colors[1].lowercased()]) == colors[0])
        // Alle belegt: zyklisch weiter
        #expect(ProjectPalette.next(after: colors) == colors[0])
        #expect(ProjectPalette.next(after: colors + [colors[0]]) == colors[1])
    }

    @Test("DurationFormat.hourMinute", arguments: durationCases)
    func hourMinute(input: TimeInterval, expected: String) {
        #expect(DurationFormat.hourMinute(input) == expected)
    }
}

/// Grenzfälle für `DurationFormat.hourMinute` (eigene Konstante, sonst scheitert die Typprüfung im Makro).
private let durationCases: [(TimeInterval, String)] = [
    (0, "0:00"),
    (59.9, "0:00"),
    (60, "0:01"),
    (65 * 60, "1:05"),
    (65 * 60 + 59, "1:05"),
    (12 * 3600 + 30 * 60, "12:30"),
    (100 * 3600, "100:00"),
    (-5, "0:00"),
    (-3600, "0:00"),
    (.nan, "0:00"),
    (.infinity, "0:00"),
]
