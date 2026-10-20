import Foundation
import Testing
@testable import TaktCore

@Suite("Auswertungen und Widget-Snapshot")
struct ReportTests {
    let day = DateInterval(start: date(2026, 10, 20), end: date(2026, 10, 21))

    @Test("recentProjects: jüngste zuerst, aufgefüllt nach sortOrder, Archiv ausgeschlossen")
    func recentProjects() throws {
        let f = try Fixture()
        let delta = Project(name: "Delta", colorHex: ProjectPalette.colors[3], sortOrder: 3)
        let archived = Project(name: "Archiv", colorHex: ProjectPalette.colors[4], sortOrder: 4)
        try f.db.saveProject(delta)
        try f.db.saveProject(archived)
        let now = date(2026, 10, 20, 18)

        // Ohne Einträge: reine sortOrder
        #expect(try f.db.recentProjects(limit: 3, now: now).map(\.name) == ["Alpha", "Beta", "Gamma"])

        try f.entry(f.gamma, date(2026, 10, 20, 8), date(2026, 10, 20, 9))
        try f.entry(f.beta, date(2026, 10, 20, 10), date(2026, 10, 20, 11))
        try f.entry(f.gamma, date(2026, 10, 19, 8), date(2026, 10, 19, 9))
        try f.entry(archived, date(2026, 10, 20, 12), date(2026, 10, 20, 13))
        try f.db.archiveProject(id: archived.id)

        #expect(try f.db.recentProjects(limit: 3, now: now).map(\.name) == ["Beta", "Gamma", "Alpha"])
        #expect(try f.db.recentProjects(limit: 10, now: now).map(\.name) == ["Beta", "Gamma", "Alpha", "Delta"])
        #expect(try f.db.recentProjects(limit: 1, now: now).map(\.name) == ["Beta"])

        // Das laufende Projekt bleibt drin
        try f.db.startTimer(projectId: f.alpha.id, now: date(2026, 10, 20, 17))
        #expect(try f.db.recentProjects(limit: 3, now: now).map(\.name) == ["Alpha", "Beta", "Gamma"])
    }

    @Test("entries(in:) liefert überlappende und laufende Einträge, sortiert")
    func entriesInInterval() throws {
        let f = try Fixture()
        try f.entry(f.alpha, date(2026, 10, 19, 22), date(2026, 10, 20, 1))   // über Mitternacht hinein
        try f.entry(f.beta, date(2026, 10, 19, 8), date(2026, 10, 19, 9))     // Vortag
        try f.entry(f.gamma, date(2026, 10, 21, 0), date(2026, 10, 21, 1))    // beginnt genau am Ende
        try f.entry(f.beta, date(2026, 10, 20, 10), date(2026, 10, 20, 11))
        try f.db.startTimer(projectId: f.gamma.id, now: date(2026, 10, 20, 15))

        let entries = try f.db.entries(in: day)
        #expect(entries.map(\.startedAt) == [date(2026, 10, 19, 22), date(2026, 10, 20, 10), date(2026, 10, 20, 15)])
    }

    @Test("totalDuration schneidet an Intervallgrenzen (über Mitternacht) und zählt Laufendes bis now")
    func totalDuration() throws {
        let f = try Fixture()
        try f.entry(f.alpha, date(2026, 10, 19, 23), date(2026, 10, 20, 1))   // 1 h am 20.
        try f.entry(f.beta, date(2026, 10, 20, 9), date(2026, 10, 20, 10, 30)) // 1,5 h
        try f.entry(f.beta, date(2026, 10, 20, 23, 30), date(2026, 10, 21, 2)) // 0,5 h am 20.

        #expect(try f.db.totalDuration(in: day, now: date(2026, 10, 22)) == 3 * hour)
        let previousDay = DateInterval(start: date(2026, 10, 19), end: date(2026, 10, 20))
        #expect(try f.db.totalDuration(in: previousDay, now: date(2026, 10, 22)) == 1 * hour)

        // Laufender Eintrag zählt bis now
        let f2 = try Fixture()
        try f2.db.startTimer(projectId: f2.alpha.id, now: date(2026, 10, 20, 14))
        #expect(try f2.db.totalDuration(in: day, now: date(2026, 10, 20, 14, 45)) == 45 * minute)
        // ... und nicht über das Intervallende hinaus
        #expect(try f2.db.totalDuration(in: day, now: date(2026, 10, 21, 3)) == 10 * hour)
    }

    @Test("totalsByProject")
    func totalsByProject() throws {
        let f = try Fixture()
        try f.entry(f.alpha, date(2026, 10, 19, 23), date(2026, 10, 20, 1))
        try f.entry(f.alpha, date(2026, 10, 20, 9), date(2026, 10, 20, 9, 30))
        try f.entry(f.beta, date(2026, 10, 20, 10), date(2026, 10, 20, 12))
        try f.db.startTimer(projectId: f.gamma.id, now: date(2026, 10, 20, 15))

        let totals = try f.db.totalsByProject(in: day, now: date(2026, 10, 20, 15, 20))
        #expect(totals == [f.alpha.id: 90 * minute, f.beta.id: 2 * hour, f.gamma.id: 20 * minute])
    }

    @Test("focusStats: Wechsel zählen")
    func focusSwitches() throws {
        let f = try Fixture()
        #expect(try f.db.focusStats(in: day, now: date(2026, 10, 21)) == FocusStats(switches: 0, longestBlock: 0))

        // A, A, B, A, C, C → Wechsel: A→B, B→A, A→C = 3
        try f.entry(f.alpha, date(2026, 10, 20, 8), date(2026, 10, 20, 9))
        try f.entry(f.alpha, date(2026, 10, 20, 9, 30), date(2026, 10, 20, 10))
        try f.entry(f.beta, date(2026, 10, 20, 10), date(2026, 10, 20, 11))
        try f.entry(f.alpha, date(2026, 10, 20, 11), date(2026, 10, 20, 11, 15))
        try f.entry(f.gamma, date(2026, 10, 20, 12), date(2026, 10, 20, 13))
        try f.entry(f.gamma, date(2026, 10, 20, 14), date(2026, 10, 20, 14, 10))

        let stats = try f.db.focusStats(in: day, now: date(2026, 10, 21))
        #expect(stats.switches == 3)
        #expect(stats.longestBlock == 1 * hour)
    }

    @Test("focusStats: Blöcke verschmelzen bei Lücke ≤ 5 Minuten, nicht darüber")
    func focusBlocks() throws {
        let f = try Fixture()
        // Alpha 9:00–10:00, Lücke 5 min, 10:05–10:50 → ein Block 9:00–10:50 = 110 min
        try f.entry(f.alpha, date(2026, 10, 20, 9), date(2026, 10, 20, 10))
        try f.entry(f.alpha, date(2026, 10, 20, 10, 5), date(2026, 10, 20, 10, 50))
        // Beta 11:00–12:00, Lücke 5 min 1 s, 12:05:01–13:00 → zwei Blöcke (60 min, ~55 min)
        try f.entry(f.beta, date(2026, 10, 20, 11), date(2026, 10, 20, 12))
        try f.entry(f.beta, date(2026, 10, 20, 12, 5, 1), date(2026, 10, 20, 13))

        let stats = try f.db.focusStats(in: day, now: date(2026, 10, 21))
        #expect(stats.switches == 1)
        #expect(stats.longestBlock == 110 * minute)
    }

    @Test("focusStats: Blöcke werden am Intervall abgeschnitten, laufende bis now")
    func focusBlocksClipped() throws {
        let f = try Fixture()
        try f.entry(f.alpha, date(2026, 10, 19, 22), date(2026, 10, 20, 2))   // 2 h im Tag
        try f.entry(f.beta, date(2026, 10, 20, 10), date(2026, 10, 20, 11))
        try f.db.startTimer(projectId: f.gamma.id, now: date(2026, 10, 20, 12))

        let stats = try f.db.focusStats(in: day, now: date(2026, 10, 20, 15))
        #expect(stats.switches == 2)
        #expect(stats.longestBlock == 3 * hour)   // laufender Gamma-Block 12–15 Uhr
    }

    @Test("widgetSnapshot im Ruhezustand")
    func snapshotIdle() throws {
        let f = try Fixture()
        try f.entry(f.beta, date(2026, 10, 20, 9), date(2026, 10, 20, 10))
        try f.entry(f.alpha, date(2026, 10, 19, 23), date(2026, 10, 20, 0, 30))  // 30 min heute

        let snapshot = try f.db.widgetSnapshot(now: date(2026, 10, 20, 12), calendar: testCalendar)
        #expect(snapshot.running == nil)
        #expect(snapshot.recent.map(\.name) == ["Beta", "Alpha", "Gamma"])
        #expect(snapshot.todayCompleted == 90 * minute)
    }

    @Test("widgetSnapshot mit laufendem Timer: recent ohne laufendes Projekt, Summe ohne laufenden Eintrag")
    func snapshotRunning() throws {
        let f = try Fixture()
        let delta = Project(name: "Delta", colorHex: ProjectPalette.colors[3], sortOrder: 3)
        try f.db.saveProject(delta)
        try f.entry(f.beta, date(2026, 10, 20, 8), date(2026, 10, 20, 9))
        try f.entry(f.gamma, date(2026, 10, 20, 9), date(2026, 10, 20, 9, 45))
        try f.entry(f.alpha, date(2026, 10, 19, 9), date(2026, 10, 19, 10))      // gestern
        let running = try f.db.startTimer(projectId: f.alpha.id, now: date(2026, 10, 20, 10))

        let snapshot = try f.db.widgetSnapshot(now: date(2026, 10, 20, 11), calendar: testCalendar)
        #expect(snapshot.running?.project == f.alpha)
        #expect(snapshot.running?.entry == running)
        #expect(snapshot.recent.map(\.name) == ["Gamma", "Beta", "Delta"])
        #expect(snapshot.todayCompleted == 105 * minute)
    }

    @Test("WidgetSnapshot.placeholder")
    func placeholder() {
        let placeholder = WidgetSnapshot.placeholder
        #expect(placeholder.running?.project.name == "Kundenportal")
        #expect(placeholder.running?.entry.isRunning == true)
        #expect(placeholder.recent.count == 2)
        #expect(!placeholder.recent.contains { $0.id == placeholder.running?.project.id })
    }
}

@Suite("ChangeNotifier")
struct ChangeNotifierTests {
    @Test("post erreicht einen Beobachter auf dem Main-Thread")
    func postAndObserve() async throws {
        let received = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let state = ObservationState(continuation)
            state.observation = ChangeNotifier.observe {
                state.finish(Thread.isMainThread)
            }
            ChangeNotifier.post()
            // Zeitlimit, damit der Test nie hängt
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { state.finish(false) }
        }
        #expect(received)
    }
}

/// Hält die Beobachtung am Leben und beendet die Continuation genau einmal.
private final class ObservationState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    var observation: ChangeObservation?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: Bool) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
