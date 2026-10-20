import Foundation
import GRDB
import Testing
@testable import TaktCore

// Erfassung v3: Migration v4, Tags, freie Tage, Stopp-Varianten, Berichte mit Wochenziel.

@Suite("Migration v3 → v4")
struct MigrationV4Tests {
    @Test("Bestehende Daten bleiben erhalten, Tag leer, Tabelle dayOff angelegt")
    func migratesData() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v3")
        let projectId = UUID()
        let finishedId = UUID()
        let runningId = UUID()
        let blockId = UUID()
        try queue.write { db in
            #expect(try !db.columns(in: "timeEntry").map(\.name).contains("tag"))
            #expect(try !db.tableExists("dayOff"))
            try db.execute(sql: """
                INSERT INTO project (id, name, colorHex, isBusiness, isArchived, sortOrder, playlistURI, createdAt,
                                     hourlyRate, isBillable, client, musicSource, budgetHours)
                VALUES (?, 'Kundenportal', '#007AFF', 1, 0, 0, NULL, ?, '92.35', 1, 'ACME GmbH', NULL, '40')
                """, arguments: [projectId, date(2026, 1, 1).databaseTime])
            try db.execute(sql: """
                INSERT INTO timeEntry (id, projectId, startedAt, endedAt, nextStep, isBillable)
                VALUES (?, ?, ?, ?, 'Tests schreiben', 0),
                       (?, ?, ?, NULL, NULL, NULL)
                """, arguments: [
                    finishedId, projectId, date(2026, 10, 19, 9).databaseTime, date(2026, 10, 19, 11).databaseTime,
                    runningId, projectId, date(2026, 10, 20, 8).databaseTime,
                ])
            try db.execute(sql: """
                INSERT INTO plannedBlock (id, projectId, startAt, note, createdAt) VALUES (?, ?, ?, 'Review', ?)
                """, arguments: [blockId, projectId, date(2026, 10, 20, 14).databaseTime, date(2026, 10, 20, 8).databaseTime])
        }

        let db = try AppDatabase(queue)  // führt v4 aus

        let project = try #require(try db.project(id: projectId))
        #expect(project.hourlyRate == Decimal(string: "92.35"))
        #expect(project.budgetHours == 40)
        let entries = try db.entries(in: DateInterval(start: date(2026, 10, 19), end: date(2026, 10, 21)))
        #expect(entries.map(\.id) == [finishedId, runningId])
        #expect(entries.allSatisfy { $0.tag == nil })
        #expect(entries.first?.nextStep == "Tests schreiben")
        #expect(entries.first?.isBillable == false)
        #expect(try db.activeEntry()?.id == runningId)
        #expect(try db.plannedBlock(now: date(2026, 10, 20, 9))?.id == blockId)
        #expect(try db.daysOff(in: DateInterval(start: date(2026, 1, 1), end: date(2027, 1, 1)), calendar: testCalendar).isEmpty)

        try queue.read { db throws in
            #expect(try AppDatabase.migrator.appliedIdentifiers(db) == ["v1", "v2", "v3", "v4"])
            #expect(try db.columns(in: "timeEntry").map(\.name).contains("tag"))
            #expect(Set(try db.columns(in: "dayOff").map(\.name)) == ["id", "date", "kind", "note"])
            #expect(try db.table("dayOff", hasUniqueKey: ["date"]))
            #expect(try db.indexes(on: "timeEntry").contains { $0.name == "timeEntry_tag" })
        }
        _ = try AppDatabase(queue)  // zweites Öffnen: nichts passiert

        // Neue Spalte nach der Migration beschreibbar.
        var finished = try #require(entries.first)
        finished.tag = "Review"
        try db.updateEntry(finished)
        #expect(try db.entries(in: DateInterval(start: date(2026, 10, 19), end: date(2026, 10, 20))).first?.tag == "Review")
    }

    @Test("Ein Datum ist eindeutig; unbekannte Arten werden zu .other")
    func dayOffConstraints() throws {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            try DayOff(date: "2026-10-21", kind: .vacation).insert(db)
            #expect(throws: DatabaseError.self) { try DayOff(date: "2026-10-21", kind: .sick).insert(db) }
            try db.execute(sql: "INSERT INTO dayOff (id, date, kind) VALUES (?, '2026-10-22', 'sabbatical')", arguments: [UUID()])
        }
        let days = try db.daysOff(in: DateInterval(start: date(2026, 10, 19), end: date(2026, 10, 26)), calendar: testCalendar)
        #expect(days.map(\.kind) == [.vacation, .other])
    }
}

@Suite("Tags")
struct TagTests {
    @Test("Normalisierung: trimmen, # entfernen, leer → nil, höchstens 40 Zeichen")
    func normalize() {
        #expect(TimeEntry.normalizedTag("  Meeting \n") == "Meeting")
        #expect(TimeEntry.normalizedTag("#Bugfix") == "Bugfix")
        #expect(TimeEntry.normalizedTag("  #  ") == nil)
        #expect(TimeEntry.normalizedTag("") == nil)
        #expect(TimeEntry.normalizedTag(nil) == nil)
        let long = String(repeating: "x", count: 50)
        #expect(TimeEntry.normalizedTag(long)?.count == 40)
    }

    @Test("addEntry/updateEntry speichern den Tag normalisiert")
    func storedNormalized() throws {
        let f = try Fixture()
        var entry = TimeEntry(projectId: f.alpha.id, startedAt: date(2026, 10, 20, 9), endedAt: date(2026, 10, 20, 10), tag: "  #Review ")
        try f.db.addEntry(entry)
        let day = DateInterval(start: date(2026, 10, 20), end: date(2026, 10, 21))
        #expect(try f.db.entries(in: day).first?.tag == "Review")
        entry.tag = "   "
        try f.db.updateEntry(entry)
        #expect(try f.db.entries(in: day).first?.tag == nil)
    }

    @Test("startTimer mit Tag; läuft das Projekt schon, bekommt der laufende Eintrag den Tag")
    func startWithTag() throws {
        let f = try Fixture()
        let first = try f.db.startTimer(projectId: f.alpha.id, tag: " Meeting ", now: date(2026, 10, 20, 9))
        #expect(first.tag == "Meeting")
        #expect(try f.db.activeEntry()?.tag == "Meeting")

        let same = try f.db.startTimer(projectId: f.alpha.id, tag: "Review", now: date(2026, 10, 20, 9, 30))
        #expect(same.id == first.id)
        #expect(try f.db.activeEntry()?.tag == "Review")
        // nil lässt den Tag stehen
        _ = try f.db.startTimer(projectId: f.alpha.id, tag: nil, now: date(2026, 10, 20, 9, 40))
        #expect(try f.db.activeEntry()?.tag == "Review")

        // Wechsel: alter Eintrag endet, neuer ohne Tag über die alte Signatur
        let other = try f.db.startTimer(projectId: f.beta.id, now: date(2026, 10, 20, 10))
        #expect(other.tag == nil)
        let entries = try f.db.entries(in: DateInterval(start: date(2026, 10, 20), end: date(2026, 10, 21)))
        #expect(entries.map(\.tag) == ["Review", nil])
        #expect(entries.first?.endedAt == date(2026, 10, 20, 10))
    }

    @Test("Vorschläge: erst Projekt, dann global, nach letzter Nutzung, Präfix, ohne Dubletten")
    func suggestions() throws {
        let f = try Fixture()
        func add(_ project: Project, _ hour: Int, _ tag: String) throws {
            try f.db.addEntry(TimeEntry(projectId: project.id, startedAt: date(2026, 10, 20, hour), endedAt: date(2026, 10, 20, hour, 30), tag: tag))
        }
        try add(f.alpha, 8, "Meeting")
        try add(f.alpha, 9, "Bugfix")
        try add(f.beta, 10, "Review")
        try add(f.beta, 11, "meeting")   // gleiche Bedeutung, jüngere Schreibweise
        try add(f.gamma, 12, "Garten")
        try add(f.alpha, 13, "Bugfix")

        #expect(try f.db.tagSuggestions(projectId: f.alpha.id, prefix: "") == ["Bugfix", "Meeting", "Garten", "Review"])
        #expect(try f.db.tagSuggestions(projectId: nil, prefix: "") == ["Bugfix", "Garten", "meeting", "Review"])
        #expect(try f.db.tagSuggestions(projectId: f.beta.id, prefix: "") == ["meeting", "Review", "Bugfix", "Garten"])
        #expect(try f.db.tagSuggestions(projectId: f.alpha.id, prefix: "ME") == ["Meeting"])
        #expect(try f.db.tagSuggestions(projectId: f.alpha.id, prefix: "#r") == ["Review"])
        #expect(try f.db.tagSuggestions(projectId: f.alpha.id, prefix: "", limit: 2) == ["Bugfix", "Meeting"])
        #expect(try f.db.tagSuggestions(projectId: f.alpha.id, prefix: "", limit: 0).isEmpty)
        #expect(try f.db.tagSuggestions(projectId: f.alpha.id, prefix: "x").isEmpty)
    }
}

@Suite("Freie Tage")
struct DayOffTests {
    @Test("Setzen, Ersetzen (gleiche ID), Abfragen, Entfernen")
    func setReplaceRemove() throws {
        let db = try AppDatabase.inMemory()
        let first = try db.setDayOff(date: date(2026, 10, 21, 15), kind: .vacation, note: "  Herbstferien ", calendar: testCalendar)
        #expect(first.date == "2026-10-21")
        #expect(first.note == "Herbstferien")
        #expect(try db.isDayOff(date: date(2026, 10, 21, 0, 0, 1), calendar: testCalendar))
        #expect(try !db.isDayOff(date: date(2026, 10, 22), calendar: testCalendar))

        let replaced = try db.setDayOff(date: date(2026, 10, 21), kind: .sick, note: " ", calendar: testCalendar)
        #expect(replaced.id == first.id)
        #expect(replaced.kind == .sick)
        #expect(replaced.note == nil)
        #expect(try db.dayOff(date: date(2026, 10, 21), calendar: testCalendar) == replaced)

        try db.removeDayOff(date: date(2026, 10, 21, 23), calendar: testCalendar)
        #expect(try !db.isDayOff(date: date(2026, 10, 21), calendar: testCalendar))
        try db.removeDayOff(date: date(2026, 10, 21), calendar: testCalendar)  // nichts da: kein Fehler
    }

    @Test("daysOff(in:): Tage im Intervall, Ende exklusiv, sortiert")
    func inInterval() throws {
        let db = try AppDatabase.inMemory()
        for (day, kind) in [(26, DayOffKind.holiday), (19, .vacation), (25, .other), (18, .sick)] {
            try db.setDayOff(date: date(2026, 10, day), kind: kind, calendar: testCalendar)
        }
        let week = DateInterval(start: date(2026, 10, 19), end: date(2026, 10, 26))
        #expect(try db.daysOff(in: week, calendar: testCalendar).map(\.date) == ["2026-10-19", "2026-10-25"])
        #expect(try db.daysOff(in: DateInterval(start: date(2026, 10, 25, 12), duration: 3600), calendar: testCalendar).map(\.kind) == [.other])
    }

    @Test("Schlüssel und Rückweg zum Datum; Titel")
    func keyAndTitle() {
        #expect(DayOff.key(for: date(2026, 1, 5, 23, 59), calendar: testCalendar) == "2026-01-05")
        #expect(DayOff(day: date(2026, 3, 9), kind: .holiday, calendar: testCalendar).startOfDay(calendar: testCalendar) == date(2026, 3, 9))
        #expect(DayOffKind.allCases.map(\.title) == ["Urlaub", "Krank", "Feiertag", "Sonstiges"])
    }
}

@Suite("Stopp-Varianten")
struct StopVariantTests {
    @Test("stopTimer(at:) stoppt mit explizitem Ende (Leerlauf abziehen)")
    func stopAt() throws {
        let f = try Fixture()
        try f.db.startTimer(projectId: f.alpha.id, now: date(2026, 10, 20, 9))
        let stopped = try f.db.stopTimer(at: date(2026, 10, 20, 10, 15), nextStep: " Weiter mit Login ")
        #expect(stopped?.endedAt == date(2026, 10, 20, 10, 15))
        #expect(stopped?.nextStep == "Weiter mit Login")
        #expect(try f.db.activeEntry() == nil)
        #expect(try f.db.stopTimer(at: date(2026, 10, 20, 11), nextStep: nil) == nil)
    }

    @Test("stopTimer(at:) mit Ende vor dem Start endet beim Start")
    func stopBeforeStart() throws {
        let f = try Fixture()
        try f.db.startTimer(projectId: f.alpha.id, now: date(2026, 10, 20, 9))
        let stopped = try f.db.stopTimer(at: date(2026, 10, 20, 8), nextStep: nil)
        #expect(stopped?.endedAt == date(2026, 10, 20, 9))
        #expect(stopped?.duration() == 0)
    }

    @Test("Leerer nextStep lässt eine Notiz vom Start stehen")
    func keepsStartNote() throws {
        let f = try Fixture()
        var running = try f.db.startTimer(projectId: f.alpha.id, now: date(2026, 10, 20, 9))
        running.nextStep = "Standup"
        try f.db.updateEntry(running)
        #expect(try f.db.stopTimer(nextStep: "  ", now: date(2026, 10, 20, 10))?.nextStep == "Standup")
    }

    @Test("discardRunning löscht den laufenden Eintrag, abgeschlossene bleiben")
    func discard() throws {
        let f = try Fixture()
        try f.entry(f.beta, date(2026, 10, 20, 7), date(2026, 10, 20, 8))
        let running = try f.db.startTimer(projectId: f.alpha.id, now: date(2026, 10, 20, 9))
        #expect(try f.db.discardRunning()?.id == running.id)
        #expect(try f.db.activeEntry() == nil)
        #expect(try f.db.entries(in: DateInterval(start: date(2026, 10, 20), end: date(2026, 10, 21))).count == 1)
        #expect(try f.db.discardRunning() == nil)
    }
}

@Suite("Berichte: Tags, Arbeitstage, Wochenziel")
struct ReportV3Tests {
    let week = ReportPeriod.week(date(2026, 10, 20))

    @Test("byTag je Projekt, nach Dauer absteigend, ohne Tag als nil")
    func byTag() throws {
        let f = try Fixture()
        func add(_ project: Project, _ day: Int, _ hour: Int, _ minutes: Int, _ tag: String?) throws {
            let start = date(2026, 10, day, hour)
            try f.db.addEntry(TimeEntry(projectId: project.id, startedAt: start, endedAt: start.addingTimeInterval(Double(minutes) * minute), tag: tag))
        }
        try add(f.alpha, 19, 9, 60, "Meeting")
        try add(f.alpha, 19, 11, 90, "Bugfix")
        try add(f.alpha, 20, 9, 30, "Meeting")
        try add(f.alpha, 20, 11, 120, nil)
        try add(f.beta, 21, 9, 45, "Review")

        let report = try f.db.report(for: week, rounding: .none, now: date(2026, 10, 25), calendar: deCalendar)
        let alpha = try #require(report.rows.first { $0.project.id == f.alpha.id })
        #expect(alpha.byTag == [
            TagReportRow(tag: nil, duration: 2 * hour, entryCount: 1),
            TagReportRow(tag: "Bugfix", duration: 90 * minute, entryCount: 1),
            TagReportRow(tag: "Meeting", duration: 90 * minute, entryCount: 2),
        ])
        let beta = try #require(report.rows.first { $0.project.id == f.beta.id })
        #expect(beta.byTag == [TagReportRow(tag: "Review", duration: 45 * minute, entryCount: 1)])
    }

    @Test("Arbeitstage: Mo–Fr ohne freie Tage; freie Tage am Wochenende zählen nicht doppelt")
    func workdays() throws {
        let f = try Fixture()
        try f.db.setDayOff(date: date(2026, 10, 21), kind: .vacation, calendar: deCalendar)  // Mi
        try f.db.setDayOff(date: date(2026, 10, 24), kind: .other, calendar: deCalendar)     // Sa
        try f.db.setDayOff(date: date(2026, 10, 27), kind: .sick, calendar: deCalendar)      // nächste Woche
        try f.entry(f.alpha, date(2026, 10, 19, 9), date(2026, 10, 19, 17))   // 8 h
        try f.entry(f.alpha, date(2026, 10, 20, 9), date(2026, 10, 20, 13))   // 4 h

        let report = try f.db.report(for: week, rounding: .none, now: date(2026, 10, 25), calendar: deCalendar)
        #expect(report.daysOff.map(\.date) == ["2026-10-21", "2026-10-24"])
        #expect(report.workdays == 4)
        #expect(report.activeDays == 2)
        #expect(report.averagePerActiveDay == 6 * hour)
        #expect(report.averagePerWorkday == 3 * hour)

        let month = try f.db.report(for: .month(date(2026, 10, 1)), rounding: .none, now: date(2026, 11, 1), calendar: deCalendar)
        #expect(month.workdays == 22 - 2)   // Oktober 2026: 22 Werktage, minus Mi 21. und Di 27.
        let saturday = try f.db.report(for: .day(date(2026, 10, 24)), rounding: .none, now: date(2026, 11, 1), calendar: deCalendar)
        #expect(saturday.workdays == 0)
        #expect(saturday.averagePerWorkday == 0)
    }

    @Test("Wochenziel: abrechenbare, ungerundete Zeit gegen anteiliges Ziel")
    func goal() throws {
        let f = try Fixture()   // gamma ist privat und damit nicht abrechenbar
        try f.db.setDayOff(date: date(2026, 10, 23), kind: .holiday, calendar: deCalendar)  // Fr
        try f.entry(f.alpha, date(2026, 10, 19, 9), date(2026, 10, 19, 19))      // 10 h
        try f.entry(f.beta, date(2026, 10, 20, 9), date(2026, 10, 20, 19, 7))    // 10:07 h
        try f.entry(f.gamma, date(2026, 10, 21, 9), date(2026, 10, 21, 14))     // 5 h privat

        let report = try f.db.report(
            for: week, rounding: .minutes30, weeklyGoal: 40 * hour, now: date(2026, 10, 25), calendar: deCalendar
        )
        let goal = try #require(report.goal)
        #expect(goal.target == 40 * hour)
        #expect(goal.achieved == 20 * hour + 7 * minute)   // ungerundet, ohne privat
        #expect(goal.adjustedTarget == 32 * hour)
        #expect(abs(goal.fraction - (20 * hour + 7 * minute) / (32 * hour)) < 1e-9)
        #expect(goal.remaining == 32 * hour - (20 * hour + 7 * minute))

        // Nur für Wochen, nur mit Ziel > 0
        #expect(try f.db.report(for: week, rounding: .none, now: date(2026, 10, 25), calendar: deCalendar).goal == nil)
        #expect(try f.db.report(for: week, rounding: .none, weeklyGoal: 0, now: date(2026, 10, 25), calendar: deCalendar).goal == nil)
        #expect(try f.db.report(for: .day(date(2026, 10, 19)), rounding: .none, weeklyGoal: 40 * hour,
                                now: date(2026, 10, 25), calendar: deCalendar).goal == nil)
    }

    @Test("Wochenziel in einer ganz freien Woche gilt als erreicht")
    func goalWithoutWorkdays() throws {
        let f = try Fixture()
        for day in 19...23 { try f.db.setDayOff(date: date(2026, 10, day), kind: .vacation, calendar: deCalendar) }
        let report = try f.db.report(for: week, rounding: .none, weeklyGoal: 40 * hour, now: date(2026, 10, 25), calendar: deCalendar)
        #expect(report.workdays == 0)
        #expect(report.goal?.adjustedTarget == 0)
        #expect(report.goal?.fraction == 1)
    }
}

@Suite("Gemeinsame Einstellungen: Wochenziel", .serialized)
struct WeeklyGoalSettingsTests {
    @Test("Standard nil, Rundreise, unsinnige Werte werden nil")
    func roundTrip() {
        let suite = "test.weeklyGoal"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(SharedSettings.weeklyGoalHours(in: defaults) == nil)
        #expect(SharedSettings.weeklyGoal(in: defaults) == nil)
        SharedSettings.setWeeklyGoalHours(37.5, in: defaults)
        #expect(SharedSettings.weeklyGoalHours(in: defaults) == 37.5)
        #expect(SharedSettings.weeklyGoal(in: defaults) == 37.5 * 3600)
        SharedSettings.setWeeklyGoalHours(nil, in: defaults)
        #expect(defaults.object(forKey: SharedSettings.weeklyGoalHoursKey) == nil)
        SharedSettings.setWeeklyGoalHours(-3, in: defaults)
        #expect(SharedSettings.weeklyGoalHours(in: defaults) == nil)
        defaults.set(500.0, forKey: SharedSettings.weeklyGoalHoursKey)
        #expect(SharedSettings.weeklyGoalHours(in: defaults) == nil)
        defaults.set(40, forKey: SharedSettings.weeklyGoalHoursKey)   // als Int geschrieben
        #expect(SharedSettings.weeklyGoalHours(in: defaults) == 40)
    }
}
