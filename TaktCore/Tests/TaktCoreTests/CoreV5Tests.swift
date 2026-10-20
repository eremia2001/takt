import Foundation
import GRDB
import Testing
@testable import TaktCore

// Core v5: Pomodoro-Zustand fürs Widget, Jahresbericht, Budget-Warnungen, Kalender, Aktivität.

// MARK: - Migration

@Suite("Migration v4 → v5")
struct MigrationV5Tests {
    @Test("Bestehende Daten bleiben erhalten, updatedAt = startedAt, neue Tabellen angelegt")
    func migratesData() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v4")
        let projectId = UUID()
        let finishedId = UUID()
        let runningId = UUID()
        try queue.write { db in
            #expect(try !db.columns(in: "timeEntry").map(\.name).contains("updatedAt"))
            #expect(try !db.tableExists("calendarEventLink"))
            try db.execute(sql: """
                INSERT INTO project (id, name, colorHex, isBusiness, isArchived, sortOrder, playlistURI, createdAt,
                                     hourlyRate, isBillable, client, musicSource, budgetHours)
                VALUES (?, 'Kundenportal', '#007AFF', 1, 0, 0, NULL, ?, '92.35', 1, 'ACME GmbH', NULL, '40')
                """, arguments: [projectId, date(2026, 1, 1).databaseTime])
            try db.execute(sql: """
                INSERT INTO timeEntry (id, projectId, startedAt, endedAt, nextStep, isBillable, tag)
                VALUES (?, ?, ?, ?, 'Tests schreiben', 0, 'Review'),
                       (?, ?, ?, NULL, NULL, NULL, NULL)
                """, arguments: [
                    finishedId, projectId, date(2026, 10, 19, 9).databaseTime, date(2026, 10, 19, 11).databaseTime,
                    runningId, projectId, date(2026, 10, 20, 8).databaseTime,
                ])
            try db.execute(sql: "INSERT INTO dayOff (id, date, kind) VALUES (?, '2026-10-21', 'vacation')", arguments: [UUID()])
        }

        let db = try AppDatabase(queue)  // führt v5 aus

        let entries = try db.entries(in: DateInterval(start: date(2026, 10, 19), end: date(2026, 10, 21)))
        #expect(entries.map(\.id) == [finishedId, runningId])
        let finished = try #require(entries.first)
        #expect(finished.updatedAt == date(2026, 10, 19, 9))
        #expect(finished.tag == "Review")
        #expect(finished.nextStep == "Tests schreiben")
        #expect(finished.isBillable == false)
        #expect(entries.last?.updatedAt == date(2026, 10, 20, 8))
        #expect(try db.activeEntry()?.id == runningId)
        #expect(try db.project(id: projectId)?.budgetHours == 40)
        #expect(try db.isDayOff(date: date(2026, 10, 21, 12), calendar: testCalendar))

        try queue.read { db throws in
            #expect(try AppDatabase.migrator.appliedIdentifiers(db) == ["v1", "v2", "v3", "v4", "v5"])
            #expect(Set(try db.columns(in: "calendarEventLink").map(\.name))
                == ["entryId", "eventIdentifier", "calendarIdentifier", "updatedAt"])
            #expect(Set(try db.columns(in: "calendarRule").map(\.name))
                == ["id", "kind", "pattern", "projectId", "sortOrder", "createdAt"])
            #expect(Set(try db.columns(in: "activityRule").map(\.name))
                == ["id", "kind", "pattern", "projectId", "sortOrder", "createdAt"])
            #expect(Set(try db.columns(in: "activitySample").map(\.name))
                == ["id", "startedAt", "endedAt", "bundleID", "windowTitle", "repoPath", "projectId"])
            #expect(try db.foreignKeys(on: "calendarEventLink").first?.destinationTable == "timeEntry")
        }
        _ = try AppDatabase(queue)  // zweites Öffnen: nichts passiert

        // Bestände sind sofort Kandidaten für die Spiegelung (ohne Verknüpfung, abgeschlossen).
        #expect(try db.entriesNeedingMirror(since: date(2026, 10, 1), minimumDuration: 5 * minute).map(\.id) == [finishedId])
    }

    @Test("updatedAt wird von addEntry, updateEntry, startTimer und stopTimer gesetzt")
    func updatedAtMaintained() throws {
        let f = try Fixture()
        var entry = TimeEntry(projectId: f.alpha.id, startedAt: date(2026, 10, 20, 8), endedAt: date(2026, 10, 20, 9))
        try f.db.addEntry(entry, now: date(2026, 10, 20, 9, 1))
        let day = DateInterval(start: date(2026, 10, 20), end: date(2026, 10, 21))
        #expect(try f.db.entries(in: day).first?.updatedAt == date(2026, 10, 20, 9, 1))

        entry.nextStep = "Weiter"
        try f.db.updateEntry(entry, now: date(2026, 10, 20, 9, 30))
        #expect(try f.db.entries(in: day).first?.updatedAt == date(2026, 10, 20, 9, 30))

        let running = try f.db.startTimer(projectId: f.beta.id, now: date(2026, 10, 20, 10))
        #expect(running.updatedAt == date(2026, 10, 20, 10))
        // Tag am laufenden Eintrag
        _ = try f.db.startTimer(projectId: f.beta.id, tag: "Meeting", now: date(2026, 10, 20, 10, 5))
        #expect(try f.db.activeEntry()?.updatedAt == date(2026, 10, 20, 10, 5))
        // Wechsel beendet den alten Eintrag
        try f.db.startTimer(projectId: f.gamma.id, now: date(2026, 10, 20, 11))
        #expect(try f.db.entries(in: day).first { $0.id == running.id }?.updatedAt == date(2026, 10, 20, 11))

        let stopped = try f.db.stopTimer(nextStep: nil, now: date(2026, 10, 20, 12))
        #expect(stopped?.updatedAt == date(2026, 10, 20, 12))
        try f.db.startTimer(projectId: f.alpha.id, now: date(2026, 10, 20, 13))
        let idleStop = try f.db.stopTimer(at: date(2026, 10, 20, 13, 30), nextStep: nil, now: date(2026, 10, 20, 14))
        #expect(idleStop?.endedAt == date(2026, 10, 20, 13, 30))
        #expect(idleStop?.updatedAt == date(2026, 10, 20, 14))
    }
}

// MARK: - Pomodoro im Widget

@Suite("Pomodoro-Zustand", .serialized)
struct PomodoroStateTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "test.pomodoro"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Rundreise als JSON, clear, fehlend und unlesbar ergeben nil")
    func roundTrip() throws {
        let defaults = freshDefaults()
        #expect(SharedSettings.pomodoro(in: defaults) == nil)

        let state = PomodoroState(
            enabled: true, phase: .shortBreak, phaseEndsAt: date(2026, 10, 20, 10, 10),
            cycle: 3, cyclesBeforeLongBreak: 4, updatedAt: date(2026, 10, 20, 10)
        )
        SharedSettings.setPomodoro(state, in: defaults)
        #expect(defaults.data(forKey: SharedSettings.pomodoroKey) != nil)
        #expect(SharedSettings.pomodoro(in: defaults) == state)

        SharedSettings.clearPomodoro(in: defaults)
        #expect(SharedSettings.pomodoro(in: defaults) == nil)

        SharedSettings.setPomodoro(state, in: defaults)
        SharedSettings.setPomodoro(nil, in: defaults)
        #expect(SharedSettings.pomodoro(in: defaults) == nil)

        defaults.set(Data("kaputt".utf8), forKey: SharedSettings.pomodoroKey)
        #expect(SharedSettings.pomodoro(in: defaults) == nil)
        defaults.removePersistentDomain(forName: "test.pomodoro")
    }

    @Test("Unbekannte Phase wird zu .idle; Restzeit und aktiv")
    func phaseAndRemaining() throws {
        let json = #"{"enabled":true,"phase":"siesta","cycle":1,"cyclesBeforeLongBreak":4,"updatedAt":0}"#
        let state = try JSONDecoder().decode(PomodoroState.self, from: Data(json.utf8))
        #expect(state.phase == .idle)
        #expect(state.phaseEndsAt == nil)
        #expect(state.remaining(at: .now) == nil)
        #expect(!state.isActive(at: .now))

        let work = PomodoroState(enabled: true, phase: .work, phaseEndsAt: date(2026, 10, 20, 10, 25))
        #expect(work.remaining(at: date(2026, 10, 20, 10)) == 25 * minute)
        #expect(work.remaining(at: date(2026, 10, 20, 11)) == 0)
        #expect(work.isActive(at: date(2026, 10, 20, 10)))
        #expect(!work.isActive(at: date(2026, 10, 20, 10, 25)))
        #expect(PomodoroState.Phase.longBreak.isBreak)
        #expect(!PomodoroState.Phase.work.isBreak)
    }

    @Test("Momentaufnahme: Pomodoro nur bei eingeschaltetem Modus; Platzhalter hat einen")
    func snapshot() throws {
        let f = try Fixture()
        let defaults = freshDefaults()
        let now = date(2026, 10, 20, 10)
        #expect(try f.db.widgetSnapshot(now: now, calendar: testCalendar, sharedDefaults: defaults).pomodoro == nil)

        let on = PomodoroState(enabled: true, phase: .work, phaseEndsAt: date(2026, 10, 20, 10, 50), cycle: 1, updatedAt: now)
        SharedSettings.setPomodoro(on, in: defaults)
        #expect(try f.db.widgetSnapshot(now: now, calendar: testCalendar, sharedDefaults: defaults).pomodoro == on)
        #expect(try f.db.widgetSnapshot(now: now, calendar: testCalendar, fixedProjectID: f.alpha.id, sharedDefaults: defaults).pomodoro == on)

        var off = on
        off.enabled = false
        SharedSettings.setPomodoro(off, in: defaults)
        #expect(try f.db.widgetSnapshot(now: now, calendar: testCalendar, sharedDefaults: defaults).pomodoro == nil)

        let placeholder = try #require(WidgetSnapshot.placeholder.pomodoro)
        #expect(placeholder.enabled)
        #expect(placeholder.phase == .work)
        #expect(placeholder.cycle == 2)
        defaults.removePersistentDomain(forName: "test.pomodoro")
    }
}

// MARK: - Jahresbericht

@Suite("Jahresbericht")
struct YearReportTests {
    @Test("Zwölf lückenlose Monate, Summen, Zuschnitt am Jahreswechsel, laufender Eintrag")
    func months() throws {
        let f = try Fixture()
        try f.entry(f.alpha, date(2026, 1, 5, 9), date(2026, 1, 5, 11))         // 2 h
        try f.entry(f.alpha, date(2026, 3, 2, 9), date(2026, 3, 2, 10))         // 1 h
        try f.entry(f.gamma, date(2026, 3, 3, 9), date(2026, 3, 3, 9, 30))      // 0:30 privat
        try f.entry(f.beta, date(2025, 12, 31, 23), date(2026, 1, 1, 1))       // 1 h im Jahr, 1 h im Vorjahr
        try f.db.startTimer(projectId: f.beta.id, now: date(2026, 10, 20, 9))   // läuft, 1 h bis now

        let report = try f.db.yearReport(year: 2026, rounding: .none, now: date(2026, 10, 20, 10), calendar: testCalendar)
        #expect(report.year == 2026)
        #expect(report.interval == DateInterval(start: date(2026, 1, 1), end: date(2027, 1, 1)))
        #expect(report.months.count == 12)
        #expect(report.months.map(\.month) == (1...12).map { date(2026, $0, 1) })
        #expect(report.months.map(\.total) == [3 * hour, 0, 90 * minute, 0, 0, 0, 0, 0, 0, hour, 0, 0])
        #expect(report.months[2].business == hour)
        #expect(report.months[2].personal == 30 * minute)
        #expect(report.months[2].activeDays == 2)
        #expect(report.months[1].activeDays == 0)

        #expect(report.total == 5.5 * hour)
        #expect(report.total == report.months.reduce(0) { $0 + $1.total })
        #expect(report.business == 5 * hour)
        #expect(report.personal == 30 * minute)
        #expect(report.activeDays == 5)
        #expect(report.averagePerActiveDay == 5.5 * hour / 5)
        #expect(report.byProject.map(\.project.id) == [f.alpha.id, f.beta.id, f.gamma.id])
        #expect(report.previousYearTotal == hour)
    }

    @Test("Kunden: zusammengefasst ohne Rücksicht auf Schreibweise, nach Betrag sortiert, ohne Kunde als nil")
    func clients() throws {
        let f = try Fixture()
        var alpha = f.alpha
        alpha.client = "ACME GmbH"
        alpha.hourlyRate = 100
        alpha.isBillable = true
        try f.db.saveProject(alpha)
        var beta = f.beta
        beta.client = " acme gmbh "
        beta.hourlyRate = 50
        try f.db.saveProject(beta)
        let delta = Project(name: "Delta", colorHex: "#FF9500", sortOrder: 3, client: "Kleinkram", hourlyRate: 80)
        try f.db.saveProject(delta)
        // Gamma: privat, ohne Kunde, ohne Satz

        try f.entry(alpha, date(2026, 2, 2, 9), date(2026, 2, 2, 11))   // 2 h × 100 = 200
        try f.entry(beta, date(2026, 2, 3, 9), date(2026, 2, 3, 13))    // 4 h × 50 = 200
        try f.entry(delta, date(2026, 2, 4, 9), date(2026, 2, 4, 10))   // 1 h × 80 = 80
        try f.entry(f.gamma, date(2026, 2, 5, 9), date(2026, 2, 5, 19)) // 10 h, kein Betrag

        let report = try f.db.yearReport(year: 2026, rounding: .none, now: date(2026, 10, 20), calendar: testCalendar)
        #expect(report.byClient.map(\.client) == ["acme gmbh", "Kleinkram", nil])  // größtes Projekt (Beta) gibt den Namen
        let acme = report.byClient[0]
        #expect(acme.duration == 6 * hour)
        #expect(acme.billableDuration == 6 * hour)
        #expect(acme.amount == 400)
        #expect(acme.projectCount == 2)
        #expect(report.byClient[1].amount == 80)
        #expect(report.byClient[2].duration == 10 * hour)
        #expect(report.byClient[2].amount == 0)
        #expect(report.amount == 480)
        #expect(report.billable == 7 * hour)
        #expect(report.months[1].amount == 480)
    }

    @Test("Vorjahr: Zeit und Betrag mit gleicher Rundung")
    func previousYear() throws {
        let f = try Fixture()
        var alpha = f.alpha
        alpha.hourlyRate = 60
        try f.db.saveProject(alpha)
        try f.entry(alpha, date(2025, 6, 2, 9), date(2025, 6, 2, 9, 10))  // 10 min → 15 min = 15,00
        try f.entry(alpha, date(2025, 12, 1, 9), date(2025, 12, 1, 10))   // 1 h = 60,00
        try f.entry(alpha, date(2024, 12, 1, 9), date(2024, 12, 1, 10))   // vorvoriges Jahr: zählt nicht

        let report = try f.db.yearReport(year: 2026, rounding: .minutes15, now: date(2026, 10, 20), calendar: testCalendar)
        #expect(report.total == 0)
        #expect(report.tagShares.isEmpty)
        #expect(report.byClient.isEmpty)
        #expect(report.months.allSatisfy { $0.total == 0 && $0.amount == 0 })
        #expect(report.previousYearTotal == 70 * minute)
        #expect(report.previousYearAmount == 75)

        let last = try f.db.yearReport(year: 2025, rounding: .minutes15, now: date(2026, 10, 20), calendar: testCalendar)
        #expect(last.total == 70 * minute)
        #expect(last.amount == 75)
        #expect(last.months[5].roundedBillable == 15 * minute)
        #expect(last.previousYearTotal == hour)
    }

    @Test("Tag-Anteile: acht größte, dann Sonstige, dann ohne Tag; Anteile ergeben 1")
    func tagShares() throws {
        let f = try Fixture()
        // Zehn Tags mit 10, 9, … 1 Minuten (über zwei Projekte verteilt), dazu 5 min ohne Tag.
        for index in 0..<10 {
            let project = index.isMultiple(of: 2) ? f.alpha : f.beta
            let start = date(2026, 4, 1 + index, 9)
            try f.db.addEntry(TimeEntry(
                projectId: project.id, startedAt: start,
                endedAt: start.addingTimeInterval(Double(10 - index) * minute), tag: "T\(index)"
            ))
        }
        // Gleicher Tag in einem anderen Projekt wird zusammengezählt.
        try f.db.addEntry(TimeEntry(projectId: f.gamma.id, startedAt: date(2026, 5, 1, 9), endedAt: date(2026, 5, 1, 9, 2), tag: "T9"))
        try f.entry(f.gamma, date(2026, 5, 2, 9), date(2026, 5, 2, 9, 5))

        let report = try f.db.yearReport(year: 2026, rounding: .none, now: date(2026, 10, 20), calendar: testCalendar)
        let shares = report.tagShares
        #expect(shares.count == 10)
        #expect(shares.prefix(8).map(\.tag) == ["T0", "T1", "T2", "T3", "T4", "T5", "T6", "T7"])
        #expect(shares[0].duration == 10 * minute)
        let other = shares[8]
        #expect(other.isOther)
        #expect(other.title == "Sonstige")
        #expect(other.duration == 2 * minute + 3 * minute)  // T8 (2) + T9 (1 + 2)
        let untagged = shares[9]
        #expect(!untagged.isOther)
        #expect(untagged.tag == nil)
        #expect(untagged.title == "ohne Tag")
        #expect(untagged.duration == 5 * minute)
        #expect(abs(shares.reduce(0) { $0 + $1.fraction } - 1) < 1e-9)
        #expect(shares[0].fraction == 10 * minute / report.total)
    }
}

// MARK: - Budget

@Suite("Budget-Warnungen")
struct BudgetUsagesTests {
    @Test("Nur aktive Projekte mit Budget, in Projektreihenfolge, laufender Eintrag bis now")
    func usages() throws {
        let f = try Fixture()
        var alpha = f.alpha
        alpha.budgetHours = 10
        try f.db.saveProject(alpha)
        var gamma = f.gamma
        gamma.budgetHours = 2
        try f.db.saveProject(gamma)
        let archived = Project(name: "Alt", colorHex: "#8E8E93", isArchived: true, sortOrder: 5, budgetHours: 1)
        try f.db.saveProject(archived)
        let zero = Project(name: "Null", colorHex: "#8E8E93", sortOrder: 6, budgetHours: 0)
        try f.db.saveProject(zero)

        try f.entry(alpha, date(2026, 9, 1, 9), date(2026, 9, 1, 17))     // 8 h
        try f.entry(archived, date(2026, 9, 2, 9), date(2026, 9, 2, 12))
        try f.entry(f.beta, date(2026, 9, 3, 9), date(2026, 9, 3, 12))    // ohne Budget
        try f.db.startTimer(projectId: gamma.id, now: date(2026, 10, 20, 9))

        let usages = try f.db.budgetUsages(now: date(2026, 10, 20, 12))
        #expect(usages.map(\.project.id) == [alpha.id, gamma.id])
        #expect(usages[0].used == 8 * hour)
        #expect(usages[0].budget == 10 * hour)
        #expect(usages[0].fraction == 0.8)
        #expect(usages[0].remaining == 2 * hour)
        #expect(usages[1].used == 3 * hour)
        #expect(usages[1].fraction == 1.5)
        #expect(usages[1].remaining == 0)

        #expect(try Fixture().db.budgetUsages().isEmpty)
    }
}

// MARK: - Kalender

@Suite("Kalender-Verknüpfungen")
struct CalendarLinkTests {
    @Test("Setzen, Ersetzen, Lesen, Entfernen; unbekannter Eintrag wirft; Löschen des Eintrags nimmt sie mit")
    func crud() throws {
        let f = try Fixture()
        let entry = try f.entry(f.alpha, date(2026, 10, 20, 9), date(2026, 10, 20, 10))
        #expect(try f.db.calendarLink(entryId: entry.id) == nil)

        let link = CalendarEventLink(entryId: entry.id, eventIdentifier: "E1", calendarIdentifier: "C1", updatedAt: date(2026, 10, 20, 10))
        try f.db.setCalendarLink(link)
        #expect(try f.db.calendarLink(entryId: entry.id) == link)
        var replaced = link
        replaced.eventIdentifier = "E2"
        try f.db.setCalendarLink(replaced)
        #expect(try f.db.calendarLinks() == [replaced])

        try f.db.removeCalendarLink(entryId: entry.id)
        #expect(try f.db.calendarLink(entryId: entry.id) == nil)
        try f.db.removeCalendarLink(entryId: entry.id)  // nichts passiert

        #expect(throws: TaktError.entryNotFound) {
            try f.db.setCalendarLink(CalendarEventLink(entryId: UUID(), eventIdentifier: "X", calendarIdentifier: "C"))
        }

        try f.db.setCalendarLink(link)
        try f.db.deleteEntry(id: entry.id)
        #expect(try f.db.calendarLinks().isEmpty)
    }

    @Test("Spiegel-Auswahl: ohne Verknüpfung oder geändert; abgeschlossen, lang genug, ab since")
    func mirrorSelection() throws {
        let f = try Fixture()
        func add(_ start: Date, _ end: Date?, updated: Date) throws -> TimeEntry {
            var entry = TimeEntry(projectId: f.alpha.id, startedAt: start, endedAt: end)
            try f.db.addEntry(entry, now: updated)
            entry.updatedAt = updated
            return entry
        }
        let old = try add(date(2026, 10, 18, 9), date(2026, 10, 18, 10), updated: date(2026, 10, 18, 10))   // vor since
        let fresh = try add(date(2026, 10, 20, 8), date(2026, 10, 20, 9), updated: date(2026, 10, 20, 9))
        let short = try add(date(2026, 10, 20, 9), date(2026, 10, 20, 9, 4), updated: date(2026, 10, 20, 9, 4))
        let synced = try add(date(2026, 10, 20, 10), date(2026, 10, 20, 11), updated: date(2026, 10, 20, 11))
        let edited = try add(date(2026, 10, 20, 12), date(2026, 10, 20, 13), updated: date(2026, 10, 20, 13))
        // Über die Grenze von since: endet danach, zählt.
        let spanning = try add(date(2026, 10, 18, 23), date(2026, 10, 19, 1), updated: date(2026, 10, 19, 1))
        try f.db.startTimer(projectId: f.beta.id, now: date(2026, 10, 20, 17))  // läuft: nie

        try f.db.setCalendarLink(CalendarEventLink(entryId: synced.id, eventIdentifier: "S", calendarIdentifier: "C", updatedAt: date(2026, 10, 20, 11, 1)))
        try f.db.setCalendarLink(CalendarEventLink(entryId: edited.id, eventIdentifier: "E", calendarIdentifier: "C", updatedAt: date(2026, 10, 20, 13, 1)))
        var changed = edited
        changed.nextStep = "Nachgetragen"
        try f.db.updateEntry(changed, now: date(2026, 10, 20, 15))

        let since = date(2026, 10, 19)
        let result = try f.db.entriesNeedingMirror(since: since, minimumDuration: 5 * minute)
        #expect(result.map(\.id) == [spanning.id, fresh.id, edited.id])
        #expect(!result.contains { $0.id == old.id || $0.id == short.id || $0.id == synced.id })
        #expect(result.last?.nextStep == "Nachgetragen")

        // Mindestdauer 0: auch der kurze Eintrag.
        #expect(try f.db.entriesNeedingMirror(since: since, minimumDuration: 0).map(\.id) == [spanning.id, fresh.id, short.id, edited.id])
    }

    @Test("Verwaiste Verknüpfungen: ohne Eintrag oder zu laufendem Eintrag")
    func orphans() throws {
        let f = try Fixture()
        let done = try f.entry(f.alpha, date(2026, 10, 20, 9), date(2026, 10, 20, 10))
        let running = try f.db.startTimer(projectId: f.beta.id, now: date(2026, 10, 20, 11))
        try f.db.setCalendarLink(CalendarEventLink(entryId: done.id, eventIdentifier: "A", calendarIdentifier: "C"))
        try f.db.setCalendarLink(CalendarEventLink(entryId: running.id, eventIdentifier: "B", calendarIdentifier: "C"))
        let ghost = UUID()
        try f.db.writer.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
            try CalendarEventLink(entryId: ghost, eventIdentifier: "G", calendarIdentifier: "C").insert(db)
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let removed = try f.db.removeOrphanLinks()
        #expect(Set(removed.map(\.eventIdentifier)) == ["B", "G"])
        #expect(try f.db.calendarLinks().map(\.entryId) == [done.id])
        #expect(try f.db.removeOrphanLinks().isEmpty)
    }
}

@Suite("Kalender-Regeln")
struct CalendarRuleTests {
    @Test("Anlegen hängt hinten an, Muster getrimmt; leeres Muster und unbekanntes Projekt werfen")
    func crud() throws {
        let f = try Fixture()
        let first = try f.db.addCalendarRule(kind: .calendarName, pattern: "  Arbeit ", projectId: f.alpha.id, now: date(2026, 10, 20))
        let second = try f.db.addCalendarRule(kind: .titleContains, pattern: "Standup", projectId: f.beta.id, now: date(2026, 10, 20))
        #expect(first.pattern == "Arbeit")
        #expect(first.sortOrder == 0)
        #expect(second.sortOrder == 1)
        #expect(try f.db.calendarRules() == [first, second])

        #expect(throws: TaktError.emptyPattern) {
            try f.db.addCalendarRule(kind: .titleContains, pattern: "   ", projectId: f.alpha.id)
        }
        #expect(throws: TaktError.projectNotFound) {
            try f.db.addCalendarRule(kind: .titleContains, pattern: "x", projectId: UUID())
        }

        var changed = second
        changed.pattern = " Daily "
        try f.db.saveCalendarRule(changed)
        #expect(try f.db.calendarRules().last?.pattern == "Daily")

        try f.db.reorderCalendarRules(ids: [second.id, first.id])
        #expect(try f.db.calendarRules().map(\.id) == [second.id, first.id])

        try f.db.deleteCalendarRule(id: second.id)
        #expect(try f.db.calendarRules().map(\.id) == [first.id])

        // Gelöschtes Projekt nimmt seine Regeln mit.
        _ = try f.db.writer.write { db in try Project.deleteOne(db, id: f.alpha.id) }
        #expect(try f.db.calendarRules().isEmpty)
    }

    @Test("Matching: erste passende Regel nach sortOrder, ohne Groß-/Kleinschreibung, Domains mit Subdomains")
    func matching() throws {
        let f = try Fixture()
        try f.db.addCalendarRule(kind: .attendeeDomain, pattern: "@ACME.de", projectId: f.alpha.id)
        try f.db.addCalendarRule(kind: .titleContains, pattern: "standup", projectId: f.beta.id)
        try f.db.addCalendarRule(kind: .calendarName, pattern: "Privat", projectId: f.gamma.id)

        #expect(try f.db.matchCalendarRule(calendarName: "Arbeit", title: "Daily STANDUP", attendeeDomains: [])?.id == f.beta.id)
        #expect(try f.db.matchCalendarRule(calendarName: "privat", title: "Zahnarzt", attendeeDomains: [])?.id == f.gamma.id)
        // Domain-Regel steht vorn und gewinnt.
        #expect(try f.db.matchCalendarRule(calendarName: "Privat", title: "Standup", attendeeDomains: ["anna@mail.acme.de"])?.id == f.alpha.id)
        #expect(try f.db.matchCalendarRule(calendarName: nil, title: nil, attendeeDomains: ["acme.de"])?.id == f.alpha.id)
        // Keine Teil-Domain-Treffer.
        #expect(try f.db.matchCalendarRule(calendarName: nil, title: nil, attendeeDomains: ["notacme.de"]) == nil)
        // Kalendername muss ganz passen.
        #expect(try f.db.matchCalendarRule(calendarName: "Privatkram", title: "Zahnarzt", attendeeDomains: []) == nil)

        // Archiviertes Projekt wird übersprungen, die nächste Regel greift.
        try f.db.addCalendarRule(kind: .titleContains, pattern: "Zahn", projectId: f.beta.id)
        try f.db.archiveProject(id: f.gamma.id)
        #expect(try f.db.matchCalendarRule(calendarName: "Privat", title: "Zahnarzt", attendeeDomains: [])?.id == f.beta.id)
    }

    @Test("Regel unbekannter Art wird übersprungen")
    func unknownKind() throws {
        let f = try Fixture()
        try f.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO calendarRule (id, kind, pattern, projectId, sortOrder, createdAt)
                VALUES (?, 'location', 'Büro', ?, 0, 0)
                """, arguments: [UUID(), f.alpha.id])
        }
        try f.db.addCalendarRule(kind: .titleContains, pattern: "Büro", projectId: f.beta.id)
        #expect(try f.db.calendarRules().count == 1)
        #expect(try f.db.matchCalendarRule(calendarName: nil, title: "Büro-Tag", attendeeDomains: [])?.id == f.beta.id)
    }
}

// MARK: - Aktivität

@Suite("Aktivitäts-Regeln und -Proben")
struct ActivityTests {
    @Test("Pfad-Normalisierung")
    func normalizedPath() {
        #expect(ActivityRule.normalizedPath("/Users/Anna/dev/Takt/") == "/users/anna/dev/takt")
        #expect(ActivityRule.normalizedPath("  /Users//anna/./dev/x/../takt ") == "/users/anna/dev/takt")
        #expect(ActivityRule.normalizedPath("~/dev")?.hasSuffix("/dev") == true)
        #expect(ActivityRule.normalizedPath("~/dev")?.hasPrefix("/") == true)
        #expect(ActivityRule.normalizedPath("file:///Users/anna/dev") == "/users/anna/dev")
        #expect(ActivityRule.normalizedPath("   ") == nil)
        #expect(ActivityRule.normalizedPath("/") == "/")
    }

    @Test("Matching: Bundle-ID exakt, Titel enthält, Repository gleich oder darunter")
    func matching() throws {
        let f = try Fixture()
        try f.db.addActivityRule(kind: .repoPath, pattern: "/Users/anna/dev/takt/", projectId: f.alpha.id)
        try f.db.addActivityRule(kind: .windowTitleContains, pattern: "kundenportal", projectId: f.beta.id)
        try f.db.addActivityRule(kind: .bundleID, pattern: "com.apple.Music", projectId: f.gamma.id)

        func match(_ bundle: String?, _ title: String?, _ repo: String?) throws -> UUID? {
            try f.db.matchActivityRule(bundleID: bundle, windowTitle: title, repoPath: repo)?.id
        }
        #expect(try match("com.apple.dt.Xcode", "Takt", "/Users/anna/dev/takt") == f.alpha.id)
        #expect(try match("com.apple.dt.Xcode", "Takt", "/users/anna/dev/takt/TaktCore") == f.alpha.id)
        #expect(try match("com.apple.dt.Xcode", "Takt", "/Users/anna/dev/takt2") == nil)
        #expect(try match("com.apple.dt.Xcode", "Takt", "/Users/anna/dev") == nil)
        #expect(try match("com.google.Chrome", "Kundenportal – Staging", nil) == f.beta.id)
        #expect(try match("COM.APPLE.MUSIC", nil, nil) == f.gamma.id)
        #expect(try match("com.apple.MusicHelper", nil, nil) == nil)
        // Reihenfolge: Repository-Regel steht vorn.
        #expect(try match("com.apple.Music", "Kundenportal", "/Users/anna/dev/takt") == f.alpha.id)

        let rules = try f.db.activityRules()
        try f.db.reorderActivityRules(ids: rules.reversed().map(\.id))
        #expect(try match("com.apple.Music", "Kundenportal", "/Users/anna/dev/takt") == f.gamma.id)

        #expect(throws: TaktError.emptyPattern) {
            try f.db.addActivityRule(kind: .bundleID, pattern: "", projectId: f.alpha.id)
        }
        var changed = rules[0]
        changed.pattern = "~/dev/takt"
        try f.db.saveActivityRule(changed)
        try f.db.deleteActivityRule(id: rules[2].id)
        #expect(try f.db.activityRules().count == 2)
    }

    @Test("Proben: Projekt per Regel, Zeitraum, Aufräumen nach 30 Tagen, Ende vor Start wirft")
    func samples() throws {
        let f = try Fixture()
        try f.db.addActivityRule(kind: .bundleID, pattern: "com.apple.dt.Xcode", projectId: f.alpha.id)

        let old = try f.db.addActivitySample(ActivitySample(
            startedAt: date(2026, 9, 10, 9), endedAt: date(2026, 9, 10, 10), bundleID: "com.apple.Safari"
        ))
        #expect(old.projectId == nil)

        let xcode = try f.db.addActivitySample(ActivitySample(
            startedAt: date(2026, 10, 20, 9), endedAt: date(2026, 10, 20, 9, 5),
            bundleID: " com.apple.dt.Xcode ", windowTitle: "  ", repoPath: " /Users/anna/dev/takt "
        ))
        #expect(xcode.projectId == f.alpha.id)
        #expect(xcode.bundleID == "com.apple.dt.Xcode")
        #expect(xcode.windowTitle == nil)
        #expect(xcode.repoPath == "/Users/anna/dev/takt")
        #expect(xcode.duration == 5 * minute)

        // Ausdrücklich gesetztes Projekt bleibt, unbekanntes wird nil, ohne Auflösung bleibt nil.
        let manual = try f.db.addActivitySample(ActivitySample(
            startedAt: date(2026, 10, 20, 9, 5), endedAt: date(2026, 10, 20, 9, 6), bundleID: "com.apple.dt.Xcode", projectId: f.beta.id
        ))
        #expect(manual.projectId == f.beta.id)
        let ghost = try f.db.addActivitySample(ActivitySample(
            startedAt: date(2026, 10, 20, 9, 6), endedAt: date(2026, 10, 20, 9, 7), bundleID: "x", projectId: UUID()
        ))
        #expect(ghost.projectId == nil)
        let unresolved = try f.db.addActivitySample(ActivitySample(
            startedAt: date(2026, 10, 20, 9, 7), endedAt: date(2026, 10, 20, 9, 8), bundleID: "com.apple.dt.Xcode"
        ), resolveProject: false)
        #expect(unresolved.projectId == nil)

        // Die alte Probe (Ende mehr als 30 Tage vor der neuen) ist beim Einfügen verschwunden.
        let all = try f.db.activitySamples(in: DateInterval(start: date(2026, 1, 1), end: date(2027, 1, 1)))
        #expect(all.map(\.id) == [xcode.id, manual.id, ghost.id, unresolved.id])
        #expect(try f.db.activitySamples(in: DateInterval(start: date(2026, 10, 20, 9, 2), end: date(2026, 10, 20, 9, 6))).map(\.id)
            == [xcode.id, manual.id])

        #expect(try f.db.pruneActivitySamples(olderThan: date(2026, 10, 20, 9, 5, 30)) == 1)
        #expect(try f.db.activitySamples(in: DateInterval(start: date(2026, 1, 1), end: date(2027, 1, 1))).map(\.id)
            == [manual.id, ghost.id, unresolved.id])

        #expect(throws: TaktError.endBeforeStart) {
            try f.db.addActivitySample(ActivitySample(startedAt: date(2026, 10, 20, 10), endedAt: date(2026, 10, 20, 9), bundleID: "x"))
        }

        // Gelöschtes Projekt: Proben bleiben, Projekt wird nil.
        _ = try f.db.writer.write { db in try Project.deleteOne(db, id: f.beta.id) }
        let remaining = try f.db.activitySamples(in: DateInterval(start: date(2026, 1, 1), end: date(2027, 1, 1)))
        #expect(remaining.count == 3)
        #expect(remaining.allSatisfy { $0.projectId == nil })
    }
}
