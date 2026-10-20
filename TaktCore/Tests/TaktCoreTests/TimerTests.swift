import Foundation
import Testing
@testable import TaktCore

@Suite("Timer, Einträge, Validierung")
struct TimerTests {
    @Test("TimeEntry: isRunning und duration")
    func entryBasics() {
        let start = date(2026, 10, 20, 9)
        var entry = TimeEntry(projectId: UUID(), startedAt: start, endedAt: nil)
        #expect(entry.isRunning)
        #expect(entry.duration(at: start + 90 * minute) == 90 * minute)
        entry.endedAt = start + 30 * minute
        #expect(!entry.isRunning)
        #expect(entry.duration(at: start + 90 * minute) == 30 * minute)
    }

    @Test("startTimer legt laufenden Eintrag an")
    func startTimer() throws {
        let f = try Fixture()
        #expect(try f.db.activeEntry() == nil)
        let now = date(2026, 10, 20, 9)
        let entry = try f.db.startTimer(projectId: f.alpha.id, now: now)
        #expect(entry.isRunning)
        #expect(entry.startedAt == now)
        #expect(try f.db.activeEntry() == entry)
    }

    @Test("startTimer stoppt den vorherigen Eintrag")
    func startStopsPrevious() throws {
        let f = try Fixture()
        let first = try f.db.startTimer(projectId: f.alpha.id, now: date(2026, 10, 20, 9))
        let second = try f.db.startTimer(projectId: f.beta.id, now: date(2026, 10, 20, 10))

        #expect(second.projectId == f.beta.id)
        #expect(try f.db.activeEntry() == second)
        let entries = try f.db.entries(in: DateInterval(start: date(2026, 10, 20), end: date(2026, 10, 21)))
        #expect(entries.count == 2)
        #expect(entries[0].id == first.id)
        #expect(entries[0].endedAt == date(2026, 10, 20, 10))
        #expect(entries.filter(\.isRunning).count == 1)
    }

    @Test("startTimer auf laufendes Projekt ist idempotent")
    func startIdempotent() throws {
        let f = try Fixture()
        let first = try f.db.startTimer(projectId: f.alpha.id, now: date(2026, 10, 20, 9))
        let again = try f.db.startTimer(projectId: f.alpha.id, now: date(2026, 10, 20, 10))
        #expect(again == first)
        #expect(try f.db.entries(in: DateInterval(start: date(2026, 10, 20), end: date(2026, 10, 21))).count == 1)
    }

    @Test("startTimer mit unbekanntem Projekt wirft")
    func startUnknownProject() throws {
        let f = try Fixture()
        #expect(throws: TaktError.projectNotFound) {
            try f.db.startTimer(projectId: UUID(), now: date(2026, 10, 20, 9))
        }
    }

    @Test("stopTimer setzt endedAt und getrimmten nächsten Schritt")
    func stopTimer() throws {
        let f = try Fixture()
        try f.db.startTimer(projectId: f.alpha.id, now: date(2026, 10, 20, 9))
        let stopped = try f.db.stopTimer(nextStep: "  Login-Seite testen \n", now: date(2026, 10, 20, 10))
        #expect(stopped?.endedAt == date(2026, 10, 20, 10))
        #expect(stopped?.nextStep == "Login-Seite testen")
        #expect(try f.db.activeEntry() == nil)
    }

    @Test("stopTimer: leerer nächster Schritt wird nil, ohne laufenden Timer nil")
    func stopTimerEmpty() throws {
        let f = try Fixture()
        #expect(try f.db.stopTimer(now: date(2026, 10, 20, 9)) == nil)
        try f.db.startTimer(projectId: f.alpha.id, now: date(2026, 10, 20, 9))
        let stopped = try f.db.stopTimer(nextStep: "   \n\t", now: date(2026, 10, 20, 10))
        #expect(stopped != nil)
        #expect(stopped?.nextStep == nil)
    }

    @Test("lastNextStep liefert den Schritt des zuletzt beendeten Eintrags")
    func lastNextStep() throws {
        let f = try Fixture()
        #expect(try f.db.lastNextStep(projectId: f.alpha.id) == nil)

        try f.entry(f.alpha, date(2026, 10, 19, 9), date(2026, 10, 19, 10), nextStep: "Alt")
        try f.entry(f.alpha, date(2026, 10, 20, 9), date(2026, 10, 20, 10), nextStep: "Neu")
        try f.entry(f.beta, date(2026, 10, 20, 11), date(2026, 10, 20, 12), nextStep: "Anderes Projekt")
        #expect(try f.db.lastNextStep(projectId: f.alpha.id) == "Neu")

        // Ein jüngerer Eintrag ohne nächsten Schritt: zählt ebenfalls (zuletzt beendet → nil)
        try f.entry(f.alpha, date(2026, 10, 20, 13), date(2026, 10, 20, 14))
        #expect(try f.db.lastNextStep(projectId: f.alpha.id) == nil)

        // Laufende Einträge werden ignoriert
        try f.db.startTimer(projectId: f.beta.id, now: date(2026, 10, 20, 15))
        #expect(try f.db.lastNextStep(projectId: f.beta.id) == "Anderes Projekt")
    }

    @Test("addEntry: Ende vor Start wird abgelehnt")
    func addEntryEndBeforeStart() throws {
        let f = try Fixture()
        #expect(throws: TaktError.endBeforeStart) {
            try f.entry(f.alpha, date(2026, 10, 20, 10), date(2026, 10, 20, 9))
        }
        // Gleicher Start und Ende ist erlaubt (Dauer 0)
        try f.entry(f.alpha, date(2026, 10, 20, 10), date(2026, 10, 20, 10))
    }

    @Test("addEntry: zweiter laufender Eintrag wird abgelehnt")
    func addEntrySecondRunning() throws {
        let f = try Fixture()
        try f.db.startTimer(projectId: f.alpha.id, now: date(2026, 10, 20, 9))
        #expect(throws: TaktError.timerAlreadyRunning) {
            try f.entry(f.beta, date(2026, 10, 20, 8), nil)
        }
        // Abgeschlossene Einträge gehen weiterhin
        try f.entry(f.beta, date(2026, 10, 20, 7), date(2026, 10, 20, 8))
    }

    @Test("updateEntry: Validierung und Speichern")
    func updateEntry() throws {
        let f = try Fixture()
        let running = try f.db.startTimer(projectId: f.alpha.id, now: date(2026, 10, 20, 9))
        var done = try f.entry(f.beta, date(2026, 10, 20, 7), date(2026, 10, 20, 8))

        // Laufender Eintrag darf sich selbst aktualisieren (bleibt laufend)
        var movedRunning = running
        movedRunning.startedAt = date(2026, 10, 20, 8, 30)
        try f.db.updateEntry(movedRunning)
        #expect(try f.db.activeEntry()?.startedAt == date(2026, 10, 20, 8, 30))

        // Abgeschlossenen Eintrag wieder öffnen, während einer läuft: verboten
        done.endedAt = nil
        #expect(throws: TaktError.timerAlreadyRunning) { try f.db.updateEntry(done) }

        done.endedAt = date(2026, 10, 20, 6)
        #expect(throws: TaktError.endBeforeStart) { try f.db.updateEntry(done) }

        done.endedAt = date(2026, 10, 20, 8, 15)
        done.nextStep = "Weiter"
        try f.db.updateEntry(done)
        let all = try f.db.entries(in: DateInterval(start: date(2026, 10, 20), end: date(2026, 10, 21)))
        #expect(all.first { $0.id == done.id } == done)

        #expect(throws: TaktError.entryNotFound) {
            try f.db.updateEntry(TimeEntry(projectId: f.alpha.id, startedAt: date(2026, 10, 20), endedAt: date(2026, 10, 20, 1)))
        }
    }

    @Test("deleteEntry entfernt den Eintrag")
    func deleteEntry() throws {
        let f = try Fixture()
        let entry = try f.entry(f.alpha, date(2026, 10, 20, 9), date(2026, 10, 20, 10))
        try f.db.deleteEntry(id: entry.id)
        #expect(try f.db.entries(in: DateInterval(start: date(2026, 10, 20), end: date(2026, 10, 21))).isEmpty)
    }

    @Test("Datumswerte überstehen den Datenbank-Rundweg exakt (auch Sub-Millisekunden)")
    func dateRoundTrip() throws {
        let f = try Fixture()
        let now = Date(timeIntervalSinceReferenceDate: 782_000_000.123456789)
        let entry = try f.db.startTimer(projectId: f.alpha.id, now: now)
        #expect(try f.db.activeEntry() == entry)
        #expect(try f.db.activeEntry()?.startedAt == now)
    }
}
