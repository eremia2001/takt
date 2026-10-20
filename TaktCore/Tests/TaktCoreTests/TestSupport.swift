import Foundation
@testable import TaktCore

/// Fester Kalender für reproduzierbare Tests (Mitternacht, Tagesgrenzen).
let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return calendar
}()

/// Baut ein Datum im Testkalender, z. B. `date(2026, 10, 20, 9, 30)`.
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    testCalendar.date(from: DateComponents(
        year: year, month: month, day: day, hour: hour, minute: minute, second: second
    ))!
}

let minute: TimeInterval = 60
let hour: TimeInterval = 3600

/// Frische In-Memory-Datenbank mit drei Projekten (sortOrder 0, 1, 2).
struct Fixture {
    let db: AppDatabase
    let alpha: Project
    let beta: Project
    let gamma: Project

    init() throws {
        db = try AppDatabase.inMemory()
        alpha = Project(name: "Alpha", colorHex: ProjectPalette.colors[0], sortOrder: 0)
        beta = Project(name: "Beta", colorHex: ProjectPalette.colors[1], sortOrder: 1)
        gamma = Project(name: "Gamma", colorHex: ProjectPalette.colors[2], isBusiness: false, sortOrder: 2)
        try db.saveProject(alpha)
        try db.saveProject(beta)
        try db.saveProject(gamma)
    }

    /// Legt einen abgeschlossenen Eintrag direkt an.
    @discardableResult
    func entry(_ project: Project, _ start: Date, _ end: Date?, nextStep: String? = nil) throws -> TimeEntry {
        let entry = TimeEntry(projectId: project.id, startedAt: start, endedAt: end, nextStep: nextStep)
        try db.addEntry(entry)
        return entry
    }
}
