import Foundation
import Testing
@testable import TaktCore

@Suite("CSV-Export")
struct CSVExportTests {
    private let rate = Decimal(string: "92.5")!

    private func lines(_ csv: String) -> [String] {
        #expect(csv.hasPrefix("\u{FEFF}"))
        #expect(csv.hasSuffix("\r\n"))
        // „\r\n“ ist in Swift ein Character – deshalb über die Skalare trennen.
        return String(csv.dropFirst()).components(separatedBy: "\r\n").dropLast()
    }

    @Test("Einträge: Kopfzeile, deutsches Format, Rundung, Betrag nur abrechenbar")
    func entries() throws {
        var alpha = Project(name: "Kundenportal", colorHex: "#007AFF", client: "ACME; Söhne", hourlyRate: rate)
        alpha.sortOrder = 0
        let garden = Project(name: "Garten", colorHex: "#34C759", isBusiness: false)
        let entries = [
            TimeEntry(projectId: garden.id, startedAt: date(2026, 10, 20, 14), endedAt: date(2026, 10, 20, 14, 40)),
            TimeEntry(projectId: alpha.id, startedAt: date(2026, 10, 20, 9, 5), endedAt: date(2026, 10, 20, 10, 32),
                      nextStep: "Login \"SSO\" fertig\nDann Tests"),
            TimeEntry(projectId: alpha.id, startedAt: date(2026, 10, 20, 11), endedAt: date(2026, 10, 20, 11, 10), isBillable: false),
            TimeEntry(projectId: UUID(), startedAt: date(2026, 10, 20, 8), endedAt: date(2026, 10, 20, 9)),  // ohne Projekt
        ]
        let csv = CSVExport.entries(entries, projects: [alpha, garden], rounding: .minutes6, calendar: testCalendar)
        let rows = lines(csv)
        #expect(rows.count == 4)  // Kopf + 3 Einträge (einer ohne Projekt fehlt)
        #expect(rows[0] == "Datum;Start;Ende;Dauer (h:mm);Dauer (dezimal);Projekt;Kunde;Business/Privat;Abrechenbar;Stundensatz;Betrag;Notiz")
        // 87 min → 90 min = 1,50 h × 92,50 = 138,75
        #expect(rows[1] == "20.10.2026;09:05;10:32;1:27;1,50;Kundenportal;\"ACME; Söhne\";Business;ja;92,50;138,75;\"Login \"\"SSO\"\" fertig\nDann Tests\"")
        // nicht abrechenbar: Satz sichtbar, kein Betrag
        #expect(rows[2] == "20.10.2026;11:00;11:10;0:10;0,20;Kundenportal;\"ACME; Söhne\";Business;nein;92,50;;")
        #expect(rows[3] == "20.10.2026;14:00;14:40;0:40;0,70;Garten;;Privat;nein;;;")
    }

    @Test("Laufender Eintrag: Ende leer, Dauer bis now; Standard-Stundensatz")
    func running() {
        let project = Project(name: "P", colorHex: "#007AFF")
        let entry = TimeEntry(projectId: project.id, startedAt: date(2026, 10, 20, 9))
        let csv = CSVExport.entries(
            [entry], projects: [project], rounding: .none, calendar: testCalendar,
            defaultHourlyRate: 60, now: date(2026, 10, 20, 9, 45)
        )
        #expect(lines(csv)[1] == "20.10.2026;09:00;;0:45;0,75;P;;Business;ja;60,00;45,00;")
    }

    @Test("Escaping")
    func escaping() {
        #expect(CSVExport.escape("einfach") == "einfach")
        #expect(CSVExport.escape("a;b") == "\"a;b\"")
        #expect(CSVExport.escape("Zitat \"x\"") == "\"Zitat \"\"x\"\"\"")
        #expect(CSVExport.escape("Zeile\r\nZwei") == "\"Zeile\r\nZwei\"")
        #expect(CSVExport.escape("a,b") == "a,b")
    }

    @Test("Summen aus dem Bericht")
    func summary() throws {
        let f = try Fixture()
        var alpha = f.alpha
        alpha.hourlyRate = rate
        try f.db.saveProject(alpha)
        try f.entry(f.alpha, date(2026, 10, 20, 9), date(2026, 10, 20, 10, 1))   // 61 min → 66 min
        try f.entry(f.gamma, date(2026, 10, 20, 11), date(2026, 10, 20, 11, 30))

        let report = try f.db.report(
            for: .day(date(2026, 10, 20)), rounding: .minutes6, now: date(2026, 10, 21), calendar: testCalendar
        )
        let rows = lines(CSVExport.summary(report, calendar: testCalendar))
        #expect(rows[0] == "Zeitraum;Dienstag, 20. Oktober 2026")
        #expect(rows[1] == "")
        #expect(rows[2] == "Projekt;Kunde;Business/Privat;Einträge;Dauer (h:mm);Dauer (dezimal);Abrechenbar (dezimal);Stundensatz;Betrag")
        #expect(rows[3] == "Alpha;;Business;1;1:01;1,10;1,10;92,50;101,75")
        #expect(rows[4] == "Gamma;;Privat;1;0:30;0,50;0,00;;")
        #expect(rows[5] == "Summe;;;2;1:31;1,60;1,10;;101,75")
    }
}

@Suite("CSV-Parser und Toggl-Import")
struct TogglImportTests {
    /// Gekürzter Toggl-„Detailed report“ mit Sonderfällen: Komma und Anführungszeichen im Feld,
    /// Zeilenumbruch im Feld, leeres Projekt, kaputte Zeile, CRLF.
    static let sample = [
        "User,Email,Client,Project,Task,Description,Billable,Start date,Start time,End date,End time,Duration,Tags,Amount (EUR)",
        "Eremiya,e@example.com,ACME,Kundenportal,,\"Login, SSO\",Yes,2026-10-19,09:00:00,2026-10-19,10:30:00,01:30:00,\"dev, backend\",120.00",
        "Eremiya,e@example.com,ACME,Kundenportal,,\"Meeting \"\"Kickoff\"\"\",No,2026-10-19,11:00:00,2026-10-19,11:15:00,00:15:00,,",
        "Eremiya,e@example.com,,Garten,,\"Hecke\nschneiden\",No,2026-10-19,17:00:00,2026-10-19,18:00:00,01:00:00,,",
        "Eremiya,e@example.com,,,,Ohne,No,2026-10-20,08:00:00,2026-10-20,08:30:00,00:30:00,,",
        "Eremiya,e@example.com,ACME,Kundenportal,,Nachts,Yes,2026-10-20,23:30:00,2026-10-21,00:30:00,01:00:00,,",
        "Eremiya,e@example.com,ACME,Kundenportal,,kaputt,Yes,2026-13-01,09:00:00,2026-13-01,10:00:00,01:00:00,,",
        "Eremiya,e@example.com,ACME,Kundenportal,,rückwärts,Yes,2026-10-22,10:00:00,2026-10-22,09:00:00,,,",
    ].joined(separator: "\r\n") + "\r\n"

    @Test("CSV-Parser: Anführungszeichen, Kommas, Zeilenumbrüche, CRLF, BOM, Leerzeilen")
    func parser() {
        let rows = CSVParser.parse("\u{FEFF}a,\"b,c\",\"d \"\"e\"\"\"\r\n\r\n\"x\ny\",,z\n\"\"\rlast")
        // Eine Zeile aus nur einem leeren Feld (auch `""`) gilt als Leerzeile.
        #expect(rows == [["a", "b,c", "d \"e\""], ["x\ny", "", "z"], ["last"]])
        #expect(CSVParser.parse("a;b", separator: ";") == [["a", "b"]])
        #expect(CSVParser.parse("").isEmpty)
    }

    @Test("parse: Einträge, Projekte, übersprungene Zeilen, Hinweise")
    func parse() throws {
        let preview = try TogglImport.parse(csv: Self.sample, calendar: testCalendar)
        #expect(preview.entries.count == 5)
        #expect(preview.skipped == 2)
        #expect(preview.newProjects == ["Kundenportal", "Garten", TogglImport.noProjectName])
        #expect(preview.warnings.contains { $0.contains("Zeile 7") })
        #expect(preview.warnings.contains { $0.contains("Zeile 8") })

        let first = preview.entries[0]
        #expect(first.projectName == "Kundenportal")
        #expect(first.client == "ACME")
        #expect(first.description == "Login, SSO")
        #expect(first.isBillable == true)
        #expect(first.start == date(2026, 10, 19, 9))
        #expect(first.end == date(2026, 10, 19, 10, 30))
        #expect(first.tags == ["dev", "backend"])
        #expect(preview.entries[1].description == "Meeting \"Kickoff\"")
        #expect(preview.entries[2].description == "Hecke\nschneiden")
        // über Mitternacht
        #expect(preview.entries[4].end == date(2026, 10, 21, 0, 30))
    }

    @Test("parse: nur Duration statt Ende; fehlende Pflichtspalten")
    func parseDurationAndErrors() throws {
        let csv = "Project,Start date,Start time,Duration\nX,2026-10-20,09:00:00,02:15:00\n"
        let preview = try TogglImport.parse(csv: csv, calendar: testCalendar)
        #expect(preview.entries.first?.end == date(2026, 10, 20, 11, 15))
        #expect(preview.entries.first?.isBillable == nil)

        #expect(throws: TogglImportError.missingColumns(["Start time", "End date"])) {
            try TogglImport.parse(csv: "Project,Start date\nX,2026-10-20\n")
        }
        #expect(throws: TogglImportError.empty) { try TogglImport.parse(csv: "") }
    }

    @Test("importToggl: Mapping, neue Projekte, Abrechenbar-Abweichung, Dubletten")
    func importEntries() throws {
        let f = try Fixture()
        let preview = try TogglImport.parse(csv: Self.sample, calendar: testCalendar)

        // „Garten“ → vorhandenes Gamma; Kundenportal und „Ohne Projekt“ neu
        let mapping: [String: UUID?] = ["Kundenportal": nil, "Garten": f.gamma.id]
        let inserted = try f.db.importToggl(preview, projectMapping: mapping, markAsBusiness: true)
        #expect(inserted == 5)

        let projects = try f.db.allProjects()
        #expect(projects.count == 5)
        let portal = try #require(projects.first { $0.name == "Kundenportal" })
        #expect(portal.isBusiness && portal.isBillable)
        #expect(portal.client == "ACME")
        #expect(portal.sortOrder == 3)
        #expect(projects.contains { $0.name == TogglImport.noProjectName && $0.sortOrder == 4 })

        let all = try f.db.entries(in: DateInterval(start: date(2026, 10, 1), end: date(2026, 11, 1)))
        #expect(all.count == 5)
        let login = try #require(all.first { $0.startedAt == date(2026, 10, 19, 9) })
        #expect(login.projectId == portal.id)
        #expect(login.nextStep == "Login, SSO")
        #expect(login.isBillable == nil)          // wie das Projekt → erbt
        let meeting = try #require(all.first { $0.startedAt == date(2026, 10, 19, 11) })
        #expect(meeting.isBillable == false)      // weicht ab → eigener Wert
        let hedge = try #require(all.first { $0.startedAt == date(2026, 10, 19, 17) })
        #expect(hedge.projectId == f.gamma.id)
        #expect(hedge.isBillable == nil)          // Gamma ist privat, Toggl „No“ → erbt

        // Zweiter Import (auch ohne Mapping): nichts doppelt, keine neuen Projekte
        #expect(try f.db.importToggl(preview, projectMapping: mapping, markAsBusiness: true) == 0)
        #expect(try f.db.importToggl(preview, projectMapping: [:], markAsBusiness: false) == 1)  // Garten → neues „Garten“
        #expect(try f.db.allProjects().count == 6)
        #expect(try f.db.importToggl(preview, projectMapping: [:], markAsBusiness: false) == 0)
    }

    @Test("importToggl: Mapping-Vorschlag nach Namen, unbekannte Projekt-ID wirft")
    func mappingSuggestion() throws {
        let f = try Fixture()
        let preview = try TogglImport.parse(
            csv: "Project,Start date,Start time,End date,End time\nalpha,2026-10-20,09:00:00,2026-10-20,10:00:00\nNeu,2026-10-20,10:00:00,2026-10-20,11:00:00\n",
            calendar: testCalendar
        )
        let suggestion = try f.db.suggestedTogglMapping(for: preview)
        let expected: [String: UUID?] = ["alpha": f.alpha.id, "Neu": UUID?.none]
        #expect(suggestion == expected)

        #expect(throws: TaktError.projectNotFound) {
            try f.db.importToggl(preview, projectMapping: ["alpha": UUID()], markAsBusiness: true)
        }
        // Transaktion: nichts gespeichert
        #expect(try f.db.allProjects().count == 3)
    }
}
