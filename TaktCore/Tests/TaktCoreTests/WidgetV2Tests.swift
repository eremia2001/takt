import Foundation
import GRDB
import Testing
@testable import TaktCore

// Datenbasis für Widget v2: Migration v3, Stundenbudget, geplanter Block, erweiterte Momentaufnahme.

@Suite("Migration v2 → v3")
struct MigrationV3Tests {
    @Test("Bestehende Daten bleiben erhalten, Budget leer, Tabelle plannedBlock angelegt")
    func migratesData() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v2")
        let projectId = UUID()
        let entryId = UUID()
        try queue.write { db in
            #expect(try !db.columns(in: "project").map(\.name).contains("budgetHours"))
            #expect(try !db.tableExists("plannedBlock"))
            try db.execute(sql: """
                INSERT INTO project (id, name, colorHex, isBusiness, isArchived, sortOrder, playlistURI, createdAt,
                                     hourlyRate, isBillable, client, musicSource)
                VALUES (?, 'Kundenportal', '#007AFF', 1, 0, 0, NULL, ?, '92.35', 1, 'ACME GmbH', 'spotify:playlist:abc')
                """, arguments: [projectId, date(2026, 1, 1).databaseTime])
            try db.execute(sql: """
                INSERT INTO timeEntry (id, projectId, startedAt, endedAt, nextStep, isBillable)
                VALUES (?, ?, ?, ?, 'Tests schreiben', 0)
                """, arguments: [entryId, projectId, date(2026, 10, 19, 9).databaseTime, date(2026, 10, 19, 11).databaseTime])
        }

        let db = try AppDatabase(queue)  // führt v3 aus

        let project = try #require(try db.project(id: projectId))
        #expect(project.name == "Kundenportal")
        #expect(project.hourlyRate == Decimal(string: "92.35"))
        #expect(project.client == "ACME GmbH")
        #expect(project.musicSource == "spotify:playlist:abc")
        #expect(project.isBillable)
        #expect(project.createdAt == date(2026, 1, 1))
        #expect(project.budgetHours == nil)

        let entries = try db.entries(in: DateInterval(start: date(2026, 10, 19), end: date(2026, 10, 20)))
        #expect(entries.count == 1)
        #expect(entries.first?.id == entryId)
        #expect(entries.first?.nextStep == "Tests schreiben")
        #expect(entries.first?.isBillable == false)
        #expect(try db.plannedBlock(now: date(2026, 10, 20)) == nil)

        try queue.read { db in
            #expect(try AppDatabase.migrator.appliedIdentifiers(db) == ["v1", "v2", "v3", "v4"])
            #expect(try db.columns(in: "project").map(\.name).contains("budgetHours"))
            let columns = Set(try db.columns(in: "plannedBlock").map(\.name))
            #expect(columns == ["id", "projectId", "startAt", "note", "createdAt"])
            let foreignKeys = try db.foreignKeys(on: "plannedBlock")
            #expect(foreignKeys.count == 1)
            #expect(foreignKeys.first?.destinationTable == "project")
        }
        _ = try AppDatabase(queue)  // zweites Öffnen: nichts passiert
    }

    @Test("Budget wird als Text gespeichert und verlustfrei gelesen")
    func budgetRoundTrip() throws {
        let db = try AppDatabase.inMemory()
        var project = Project(name: "Portal", colorHex: "#007AFF", budgetHours: Decimal(string: "12.5")!)
        try db.saveProject(project)
        #expect(try db.project(id: project.id) == project)
        let (stored, type) = try db.writer.read { db in
            (
                try String.fetchOne(db, sql: "SELECT budgetHours FROM project WHERE id = ?", arguments: [project.id]),
                try String.fetchOne(db, sql: "SELECT typeof(budgetHours) FROM project WHERE id = ?", arguments: [project.id])
            )
        }
        #expect(stored == "12.5")
        #expect(type == "text")
        #expect(project.budgetInterval == 12.5 * hour)

        project.budgetHours = nil
        try db.saveProject(project)
        #expect(try db.project(id: project.id)?.budgetHours == nil)
        #expect(project.budgetInterval == nil)
        #expect(Project(name: "X", colorHex: "#007AFF", budgetHours: 0).budgetInterval == nil)
    }
}

@Suite("Geplanter Block")
struct PlannedBlockTests {
    @Test("Planen, Ersetzen, Löschen")
    func planReplaceClear() throws {
        let f = try Fixture()
        let now = date(2026, 10, 20, 10)
        #expect(try f.db.plannedBlock(now: now) == nil)

        let first = try f.db.setPlannedBlock(projectId: f.alpha.id, startAt: date(2026, 10, 20, 14), note: "  Login  ", now: now)
        #expect(first.note == "Login")
        #expect(first.createdAt == now)
        #expect(try f.db.plannedBlock(now: now) == first)

        // Ersetzen: es bleibt genau einer.
        let second = try f.db.setPlannedBlock(projectId: f.beta.id, startAt: date(2026, 10, 20, 16), note: " ", now: now)
        #expect(second.note == nil)
        #expect(try f.db.plannedBlock(now: now) == second)
        #expect(try f.db.writer.read { try PlannedBlock.fetchCount($0) } == 1)

        try f.db.clearPlannedBlock()
        #expect(try f.db.plannedBlock(now: now) == nil)
        #expect(try f.db.writer.read { try PlannedBlock.fetchCount($0) } == 0)
    }

    @Test("Unbekanntes Projekt wirft")
    func unknownProject() throws {
        let f = try Fixture()
        #expect(throws: TaktError.projectNotFound) {
            try f.db.setPlannedBlock(projectId: UUID(), startAt: date(2026, 10, 20, 14))
        }
    }

    @Test("Fällige Blöcke bleiben 4 Stunden sichtbar, ältere werden ignoriert und beim Setzen gelöscht")
    func expiry() throws {
        let f = try Fixture()
        let block = try f.db.setPlannedBlock(projectId: f.alpha.id, startAt: date(2026, 10, 20, 14), now: date(2026, 10, 20, 9))
        #expect(try f.db.plannedBlock(now: date(2026, 10, 20, 14)) == block)
        #expect(try f.db.plannedBlock(now: date(2026, 10, 20, 18)) == block)        // genau 4 h danach
        #expect(try f.db.plannedBlock(now: date(2026, 10, 20, 18, 0, 1)) == nil)   // danach abgelaufen

        try f.db.setPlannedBlock(projectId: f.beta.id, startAt: date(2026, 10, 21, 9), now: date(2026, 10, 20, 19))
        let all = try f.db.writer.read { try PlannedBlock.fetchAll($0) }
        #expect(all.map(\.projectId) == [f.beta.id])
    }

    @Test("Start löscht einen fälligen Block desselben Projekts")
    func startClearsDueBlock() throws {
        let f = try Fixture()
        // 14:00 geplant, Start um 13:50 (innerhalb von 15 min) → erledigt.
        try f.db.setPlannedBlock(projectId: f.alpha.id, startAt: date(2026, 10, 20, 14), now: date(2026, 10, 20, 9))
        try f.db.startTimer(projectId: f.alpha.id, now: date(2026, 10, 20, 13, 50))
        #expect(try f.db.plannedBlock(now: date(2026, 10, 20, 13, 50)) == nil)
    }

    @Test("Start lässt fremde und noch nicht fällige Blöcke stehen")
    func startKeepsOtherBlocks() throws {
        let f = try Fixture()
        let block = try f.db.setPlannedBlock(projectId: f.alpha.id, startAt: date(2026, 10, 20, 14), now: date(2026, 10, 20, 9))

        // Anderes Projekt, Block fällig → bleibt.
        try f.db.startTimer(projectId: f.beta.id, now: date(2026, 10, 20, 14, 5))
        #expect(try f.db.plannedBlock(now: date(2026, 10, 20, 14, 5)) == block)

        // Gleiches Projekt, aber mehr als 15 Minuten vorher → bleibt.
        try f.db.stopTimer(now: date(2026, 10, 20, 14, 10))
        let later = try f.db.setPlannedBlock(projectId: f.alpha.id, startAt: date(2026, 10, 20, 17), now: date(2026, 10, 20, 14, 10))
        try f.db.startTimer(projectId: f.alpha.id, now: date(2026, 10, 20, 16, 44))
        #expect(try f.db.plannedBlock(now: date(2026, 10, 20, 16, 44)) == later)
    }

    @Test("Start eines schon laufenden Projekts erledigt dessen fälligen Block ebenfalls")
    func startRunningProjectClearsBlock() throws {
        let f = try Fixture()
        try f.db.startTimer(projectId: f.alpha.id, now: date(2026, 10, 20, 13))
        try f.db.setPlannedBlock(projectId: f.alpha.id, startAt: date(2026, 10, 20, 14), now: date(2026, 10, 20, 13))
        try f.db.startTimer(projectId: f.alpha.id, now: date(2026, 10, 20, 14))
        #expect(try f.db.plannedBlock(now: date(2026, 10, 20, 14)) == nil)
    }

    @Test("Gelöschtes Projekt nimmt seinen Block mit (onDelete cascade)")
    func cascade() throws {
        let f = try Fixture()
        try f.db.setPlannedBlock(projectId: f.gamma.id, startAt: date(2026, 10, 20, 14), now: date(2026, 10, 20, 9))
        _ = try f.db.writer.write { try Project.deleteOne($0, id: f.gamma.id) }
        #expect(try f.db.plannedBlock(now: date(2026, 10, 20, 9)) == nil)
    }
}

@Suite("Stundenbudget")
struct BudgetTests {
    @Test("Verbrauch über alle Einträge, laufende bis jetzt")
    func usage() throws {
        let f = try Fixture()
        var alpha = f.alpha
        alpha.budgetHours = 40
        try f.db.saveProject(alpha)

        // Ohne Einträge
        var usage = try f.db.budgetUsage(projectId: alpha.id, now: date(2026, 10, 20, 12))
        #expect(usage.used == 0)
        #expect(usage.budget == 40 * hour)

        try f.entry(alpha, date(2026, 9, 1, 9), date(2026, 9, 1, 17))          // 8 h, Vormonat
        try f.entry(alpha, date(2026, 10, 19, 23), date(2026, 10, 20, 1))       // 2 h über Mitternacht
        try f.entry(f.beta, date(2026, 10, 20, 8), date(2026, 10, 20, 9))       // anderes Projekt
        try f.db.startTimer(projectId: alpha.id, now: date(2026, 10, 20, 10))

        usage = try f.db.budgetUsage(projectId: alpha.id, now: date(2026, 10, 20, 11, 30))
        #expect(usage.used == 8 * hour + 2 * hour + 90 * minute)
        #expect(usage.budget == 40 * hour)

        // Projekt ohne Budget
        let beta = try f.db.budgetUsage(projectId: f.beta.id, now: date(2026, 10, 20, 12))
        #expect(beta.used == 1 * hour)
        #expect(beta.budget == nil)

        #expect(throws: TaktError.projectNotFound) {
            try f.db.budgetUsage(projectId: UUID())
        }
    }

    @Test("Laufender Eintrag mit Beginn nach now zählt 0")
    func futureRunning() throws {
        let f = try Fixture()
        try f.db.startTimer(projectId: f.alpha.id, now: date(2026, 10, 20, 12))
        #expect(try f.db.budgetUsage(projectId: f.alpha.id, now: date(2026, 10, 20, 11)).used == 0)
    }
}

@Suite("Momentaufnahme Widget v2", .serialized)
struct WidgetSnapshotV2Tests {
    private func freshDefaults() -> UserDefaults {
        let suite = "test.widget-v2"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Alpha läuft seit 10:00 (Budget 10 h, vorher 3 h), Beta 8–9, Gamma 9–9:30, Delta archiviert.
    private func scenario() throws -> (Fixture, Project, Project) {
        let f = try Fixture()
        var alpha = f.alpha
        alpha.budgetHours = 10
        try f.db.saveProject(alpha)
        let delta = Project(name: "Delta", colorHex: ProjectPalette.colors[3], isArchived: true, sortOrder: 3)
        try f.db.saveProject(delta)

        try f.entry(alpha, date(2026, 10, 19, 13), date(2026, 10, 19, 16), nextStep: "Login testen")
        try f.entry(f.beta, date(2026, 10, 20, 8), date(2026, 10, 20, 9))
        try f.entry(f.gamma, date(2026, 10, 20, 9), date(2026, 10, 20, 9, 30))
        try f.db.startTimer(projectId: alpha.id, now: date(2026, 10, 20, 10))
        return (f, alpha, delta)
    }

    @Test("Alle neuen Felder ohne festes Projekt")
    func fullSnapshot() throws {
        let (f, alpha, _) = try scenario()
        try f.db.setPlannedBlock(projectId: f.beta.id, startAt: date(2026, 10, 20, 14), note: "Deploy", now: date(2026, 10, 20, 9))
        let defaults = freshDefaults()
        let now = date(2026, 10, 20, 11)

        let snapshot = try f.db.widgetSnapshot(now: now, calendar: testCalendar, sharedDefaults: defaults)
        #expect(snapshot.running?.project.id == alpha.id)
        #expect(snapshot.recent.map(\.id) == [f.gamma.id, f.beta.id])
        #expect(snapshot.switchTargets.map(\.id) == [f.gamma.id, f.beta.id])
        #expect(snapshot.allProjects.map(\.id) == [alpha.id, f.beta.id, f.gamma.id])  // ohne archiviertes
        #expect(snapshot.todayCompleted == 90 * minute)
        #expect(snapshot.todayEntries.map(\.projectId) == [f.beta.id, f.gamma.id, alpha.id])
        #expect(snapshot.todayEntries.first?.colorHex == f.beta.colorHex)
        #expect(snapshot.todayEntries.last?.isRunning == true)
        #expect(snapshot.runningNextStep == "Login testen")
        #expect(snapshot.plannedBlock == WidgetSnapshot.PlannedBlockInfo(project: f.beta, startAt: date(2026, 10, 20, 14), note: "Deploy"))
        #expect(snapshot.plannedBlock?.isDue(at: now) == false)
        #expect(snapshot.breakReminderMinutes == 75)
        #expect(snapshot.fixedProjectID == nil)
        #expect(!snapshot.fixedProjectRunningElsewhere)

        let budget = try #require(snapshot.runningBudget)
        #expect(budget.budget == 10 * hour)
        #expect(budget.used == 4 * hour)
        #expect(budget.completed == 3 * hour)
        #expect(budget.fraction == 0.4)
        #expect(budget.used(at: date(2026, 10, 20, 12), runningSince: date(2026, 10, 20, 10)) == 5 * hour)
    }

    @Test("Wechselziele: höchstens zwei, ohne das laufende")
    func switchTargets() throws {
        let f = try Fixture()
        let delta = Project(name: "Delta", colorHex: ProjectPalette.colors[3], sortOrder: 3)
        try f.db.saveProject(delta)
        try f.entry(f.alpha, date(2026, 10, 20, 8), date(2026, 10, 20, 9))
        try f.entry(f.beta, date(2026, 10, 20, 9), date(2026, 10, 20, 10))
        try f.entry(f.gamma, date(2026, 10, 20, 10), date(2026, 10, 20, 11))
        try f.db.startTimer(projectId: delta.id, now: date(2026, 10, 20, 11))

        let snapshot = try f.db.widgetSnapshot(now: date(2026, 10, 20, 12), calendar: testCalendar, sharedDefaults: freshDefaults())
        #expect(snapshot.recent.map(\.id) == [f.gamma.id, f.beta.id, f.alpha.id])
        #expect(snapshot.switchTargets.map(\.id) == [f.gamma.id, f.beta.id])
        #expect(snapshot.allProjects.count == 4)
    }

    @Test("Ohne Budget, ohne Block, Erinnerung aus, Nächster Schritt nur bei laufendem Timer")
    func emptyOptionals() throws {
        let f = try Fixture()
        try f.entry(f.beta, date(2026, 10, 20, 8), date(2026, 10, 20, 9), nextStep: "Weiter")
        let defaults = freshDefaults()
        SharedSettings.setBreakReminderEnabled(false, in: defaults)

        var snapshot = try f.db.widgetSnapshot(now: date(2026, 10, 20, 12), calendar: testCalendar, sharedDefaults: defaults)
        #expect(snapshot.running == nil)
        #expect(snapshot.runningNextStep == nil)
        #expect(snapshot.runningBudget == nil)
        #expect(snapshot.plannedBlock == nil)
        #expect(snapshot.breakReminderMinutes == nil)

        try f.db.startTimer(projectId: f.beta.id, now: date(2026, 10, 20, 12))
        SharedSettings.setBreakReminderEnabled(true, in: defaults)
        SharedSettings.setBreakReminderMinutes(50, in: defaults)
        snapshot = try f.db.widgetSnapshot(now: date(2026, 10, 20, 12, 30), calendar: testCalendar, sharedDefaults: defaults)
        #expect(snapshot.runningNextStep == "Weiter")
        #expect(snapshot.runningBudget == nil)  // Beta hat kein Budget
        #expect(snapshot.breakReminderMinutes == 50)
    }

    @Test("Tagesleiste: Einträge über Mitternacht werden auf heute zugeschnitten")
    func todayEntriesClipped() throws {
        let f = try Fixture()
        try f.entry(f.alpha, date(2026, 10, 19, 23), date(2026, 10, 20, 1))
        try f.entry(f.beta, date(2026, 10, 20, 23), date(2026, 10, 21, 2))
        let snapshot = try f.db.widgetSnapshot(now: date(2026, 10, 20, 23, 30), calendar: testCalendar, sharedDefaults: freshDefaults())
        #expect(snapshot.todayEntries.count == 2)
        #expect(snapshot.todayEntries[0].startedAt == date(2026, 10, 20))
        #expect(snapshot.todayEntries[0].endedAt == date(2026, 10, 20, 1))
        #expect(snapshot.todayEntries[1].startedAt == date(2026, 10, 20, 23))
        #expect(snapshot.todayEntries[1].endedAt == date(2026, 10, 21))
    }

    @Test("Geplanter Block eines archivierten Projekts wird nicht gezeigt")
    func archivedBlockHidden() throws {
        let (f, _, delta) = try scenario()
        try f.db.setPlannedBlock(projectId: delta.id, startAt: date(2026, 10, 20, 14), now: date(2026, 10, 20, 9))
        let snapshot = try f.db.widgetSnapshot(now: date(2026, 10, 20, 11), calendar: testCalendar, sharedDefaults: freshDefaults())
        #expect(snapshot.plannedBlock == nil)
    }

    @Test("Ein-Projekt-Widget: festes Projekt läuft")
    func fixedRunning() throws {
        let (f, alpha, _) = try scenario()
        try f.db.setPlannedBlock(projectId: alpha.id, startAt: date(2026, 10, 20, 15), now: date(2026, 10, 20, 9))
        let snapshot = try f.db.widgetSnapshot(
            now: date(2026, 10, 20, 11), calendar: testCalendar, fixedProjectID: alpha.id, sharedDefaults: freshDefaults()
        )
        #expect(snapshot.fixedProjectID == alpha.id)
        #expect(snapshot.running?.project.id == alpha.id)
        #expect(!snapshot.fixedProjectRunningElsewhere)
        #expect(snapshot.recent.isEmpty)
        #expect(snapshot.switchTargets.isEmpty)
        #expect(snapshot.allProjects.map(\.id) == [alpha.id])
        #expect(snapshot.todayCompleted == 0)                   // Alpha heute nur laufend
        #expect(snapshot.todayEntries.count == 3)               // Tagesleiste vollständig
        #expect(snapshot.plannedBlock?.project.id == alpha.id)
        #expect(snapshot.runningBudget?.used == 4 * hour)
        #expect(snapshot.runningNextStep == "Login testen")
    }

    @Test("Ein-Projekt-Widget: anderes Projekt läuft")
    func fixedRunningElsewhere() throws {
        let (f, alpha, _) = try scenario()
        try f.db.setPlannedBlock(projectId: alpha.id, startAt: date(2026, 10, 20, 15), now: date(2026, 10, 20, 9))
        let snapshot = try f.db.widgetSnapshot(
            now: date(2026, 10, 20, 11), calendar: testCalendar, fixedProjectID: f.beta.id, sharedDefaults: freshDefaults()
        )
        #expect(snapshot.running == nil)
        #expect(snapshot.fixedProjectRunningElsewhere)
        #expect(snapshot.recent.map(\.id) == [f.beta.id])
        #expect(snapshot.switchTargets.map(\.id) == [f.beta.id])
        #expect(snapshot.allProjects.map(\.id) == [f.beta.id])
        #expect(snapshot.todayCompleted == 1 * hour)
        #expect(snapshot.plannedBlock == nil)                   // Block gehört zu Alpha
        #expect(snapshot.runningBudget == nil)                  // Beta hat kein Budget
        #expect(snapshot.runningNextStep == nil)
    }

    @Test("Ein-Projekt-Widget: Budget des festen Projekts auch ohne laufenden Timer")
    func fixedIdleBudget() throws {
        let (f, alpha, _) = try scenario()
        try f.db.stopTimer(now: date(2026, 10, 20, 11))
        let snapshot = try f.db.widgetSnapshot(
            now: date(2026, 10, 20, 12), calendar: testCalendar, fixedProjectID: alpha.id, sharedDefaults: freshDefaults()
        )
        #expect(snapshot.running == nil)
        #expect(!snapshot.fixedProjectRunningElsewhere)
        #expect(snapshot.recent.map(\.id) == [alpha.id])
        #expect(snapshot.todayCompleted == 1 * hour)
        let budget = try #require(snapshot.runningBudget)
        #expect(budget.used == 4 * hour)
        #expect(budget.completed == 4 * hour)
    }

    @Test("Ein-Projekt-Widget: unbekanntes Projekt ergibt leere Listen")
    func fixedUnknown() throws {
        let (f, _, _) = try scenario()
        let snapshot = try f.db.widgetSnapshot(
            now: date(2026, 10, 20, 11), calendar: testCalendar, fixedProjectID: UUID(), sharedDefaults: freshDefaults()
        )
        #expect(snapshot.running == nil)
        #expect(snapshot.fixedProjectRunningElsewhere)
        #expect(snapshot.recent.isEmpty)
        #expect(snapshot.allProjects.isEmpty)
        #expect(snapshot.todayCompleted == 0)
        #expect(snapshot.runningBudget == nil)
    }

    @Test("Alte Initialisierung bleibt nutzbar, Platzhalter ist vollständig")
    func compatibilityAndPlaceholder() {
        let project = Project(name: "A", colorHex: "#007AFF")
        let old = WidgetSnapshot(running: nil, recent: [project], todayCompleted: 60)
        #expect(old.switchTargets == [project])
        #expect(old.allProjects.isEmpty)
        #expect(old.plannedBlock == nil)
        #expect(!old.fixedProjectRunningElsewhere)

        let placeholder = WidgetSnapshot.placeholder
        #expect(placeholder.running != nil)
        #expect(placeholder.switchTargets.count == 2)
        #expect(placeholder.allProjects.count == 3)
        #expect(placeholder.todayEntries.count == 3)
        #expect(placeholder.runningNextStep != nil)
        #expect(placeholder.plannedBlock.map { $0.startAt > .now } == true)
        #expect(placeholder.breakReminderMinutes == 75)
        #expect(placeholder.runningBudget?.budget == 40 * hour)
        #expect(placeholder.runningBudget?.used == 12.5 * hour)
    }
}

@Suite("Gemeinsame Einstellungen: Pausenerinnerung", .serialized)
struct SharedBreakSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "test.break"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Standardwerte: an, 75 Minuten; unsinnige Werte fallen auf 75 zurück")
    func defaults() {
        let defaults = freshDefaults()
        #expect(SharedSettings.breakReminderEnabled(in: defaults))
        #expect(SharedSettings.breakReminderMinutes(in: defaults) == 75)
        #expect(SharedSettings.breakReminderMinutesIfEnabled(in: defaults) == 75)
        defaults.set(0, forKey: SharedSettings.breakReminderMinutesKey)
        #expect(SharedSettings.breakReminderMinutes(in: defaults) == 75)
    }

    @Test("Rundreise und aus = nil")
    func roundTrip() {
        let defaults = freshDefaults()
        SharedSettings.setBreakReminderMinutes(90, in: defaults)
        SharedSettings.setBreakReminderEnabled(false, in: defaults)
        #expect(defaults.integer(forKey: "breakReminderMinutes") == 90)
        #expect(defaults.bool(forKey: "breakReminderEnabled") == false)
        #expect(SharedSettings.breakReminderMinutes(in: defaults) == 90)
        #expect(SharedSettings.breakReminderMinutesIfEnabled(in: defaults) == nil)
        SharedSettings.setBreakReminderEnabled(true, in: defaults)
        #expect(SharedSettings.breakReminderMinutesIfEnabled(in: defaults) == 90)
    }
}
