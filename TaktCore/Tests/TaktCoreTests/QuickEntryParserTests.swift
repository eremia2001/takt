import Foundation
import Testing
@testable import TaktCore

@Suite("Schnelleingabe")
struct QuickEntryParserTests {
    let portal = Project(name: "Kundenportal", colorHex: "#007AFF", sortOrder: 0)
    let garden = Project(name: "Garten", colorHex: "#34C759", isBusiness: false, sortOrder: 1)
    let taxes = Project(name: "Steuer", colorHex: "#8E8E93", isBusiness: false, sortOrder: 2)
    let website = Project(name: "Website", colorHex: "#5856D6", sortOrder: 3)
    let webshop = Project(name: "Webshop", colorHex: "#FF9500", sortOrder: 4)
    let office = Project(name: "Büro & Verwaltung", colorHex: "#A2845E", sortOrder: 5)

    var projects: [Project] { [portal, garden, taxes, website, webshop, office] }
    /// Dienstag, 20.10.2026, 18:00 (Berlin).
    let now = date(2026, 10, 20, 18)

    private func parse(_ text: String, projects: [Project]? = nil, now: Date? = nil) -> Result<QuickEntry, QuickEntryError> {
        QuickEntryParser.parse(text, projects: projects ?? self.projects, now: now ?? self.now, calendar: testCalendar)
    }

    private func entry(_ text: String, projects: [Project]? = nil, now: Date? = nil) throws -> QuickEntry {
        try parse(text, projects: projects, now: now).get()
    }

    private func error(_ text: String, projects: [Project]? = nil, now: Date? = nil) -> QuickEntryError? {
        if case .failure(let error) = parse(text, projects: projects, now: now) { return error }
        return nil
    }

    // MARK: Beispiele aus der Vorgabe

    @Test("Kundenportal 9:00-10:30 Review")
    func fullRange() throws {
        let e = try entry("Kundenportal 9:00-10:30 Review")
        #expect(e.projectId == portal.id)
        #expect(e.projectName == "Kundenportal")
        #expect(e.start == date(2026, 10, 20, 9))
        #expect(e.end == date(2026, 10, 20, 10, 30))
        #expect(e.note == "Review")
        #expect(e.tag == nil)
        #expect(!e.isRunningStart)
        #expect(e.duration == 90 * minute)
    }

    @Test("kunden 9-10:30 #meeting Standup")
    func prefixTagNote() throws {
        let e = try entry("kunden 9-10:30 #meeting Standup")
        #expect(e.projectId == portal.id)
        #expect(e.start == date(2026, 10, 20, 9))
        #expect(e.end == date(2026, 10, 20, 10, 30))
        #expect(e.tag == "meeting")
        #expect(e.note == "Standup")
    }

    @Test("Garten 14:00 bis 15:15")
    func bis() throws {
        let e = try entry("Garten 14:00 bis 15:15")
        #expect(e.projectId == garden.id)
        #expect(e.start == date(2026, 10, 20, 14))
        #expect(e.end == date(2026, 10, 20, 15, 15))
        #expect(e.note == nil)
    }

    @Test("Steuer gestern 20:00-21:00")
    func yesterday() throws {
        let e = try entry("Steuer gestern 20:00-21:00")
        #expect(e.projectId == taxes.id)
        #expect(e.start == date(2026, 10, 19, 20))
        #expect(e.end == date(2026, 10, 19, 21))
    }

    @Test("Website 1h30 und Website 45m: Dauer bis jetzt")
    func durations() throws {
        let long = try entry("Website 1h30")
        #expect(long.projectId == website.id)
        #expect(long.end == now)
        #expect(long.start == now.addingTimeInterval(-90 * minute))
        #expect(!long.isRunningStart)

        let short = try entry("Website 45m")
        #expect(short.start == now.addingTimeInterval(-45 * minute))
        #expect(short.end == now)
    }

    @Test("Weitere Dauerformen")
    func durationForms() throws {
        let cases: [(String, TimeInterval)] = [
            ("Website 90min", 90 * minute), ("Website 1,5h", 90 * minute), ("Website 1:30h", 90 * minute),
            ("Website 2 Std", 2 * hour), ("Website 1h 15m", 75 * minute), ("Website 30 min", 30 * minute),
            ("Website 1h", hour),
        ]
        for (text, duration) in cases {
            #expect(try entry(text).duration == duration, "\(text)")
        }
    }

    @Test("Website allein startet den Timer jetzt")
    func runningStart() throws {
        let e = try entry("Website")
        #expect(e.projectId == website.id)
        #expect(e.isRunningStart)
        #expect(e.start == now)
        #expect(e.end == nil)
        #expect(e.duration == nil)

        let tagged = try entry("Website #Bugfix Login reparieren")
        #expect(tagged.isRunningStart)
        #expect(tagged.tag == "Bugfix")
        #expect(tagged.note == "Login reparieren")
    }

    @Test("Mo 9-11 Kundenportal: Wochentag vorn, Projekt hinter der Zeit")
    func weekdayFirst() throws {
        let e = try entry("Mo 9-11 Kundenportal Konzept")
        #expect(e.projectId == portal.id)
        #expect(e.start == date(2026, 10, 19, 9))
        #expect(e.end == date(2026, 10, 19, 11))
        #expect(e.note == "Konzept")
    }

    // MARK: Projektsuche

    @Test("Mehrdeutig: zwei gleich gute Treffer")
    func ambiguous() {
        #expect(error("web 9-10") == .ambiguousProject([website, webshop]))
    }

    @Test("Unbekanntes Projekt")
    func unknown() {
        #expect(error("Zahnarzt 9-10") == .unknownProject("Zahnarzt"))
        #expect(error("xyz") == .unknownProject("xyz"))
    }

    @Test("Teilwort, Tippfehler, Akzente, Wortanfang")
    func fuzzy() throws {
        #expect(try entry("portal 9-10").projectId == portal.id)        // Teilwort
        #expect(try entry("kundeportal 9-10").projectId == portal.id)   // ein Tippfehler
        #expect(try entry("buro 1h").projectId == office.id)            // ü = u
        #expect(try entry("verwaltung 1h").projectId == office.id)      // Wortanfang
        #expect(try entry("WEBSITE 1h").projectId == website.id)        // Groß/klein
        #expect(try entry("wbst 1h").projectId == website.id)           // Buchstabenfolge
    }

    @Test("Längster passender Projektname, Rest ist Notiz")
    func longestPrefix() throws {
        let relaunch = Project(name: "Website Relaunch", colorHex: "#007AFF")
        let list = [website, relaunch]
        #expect(try entry("Website Relaunch 1h", projects: list).projectId == relaunch.id)
        let bugfix = try entry("Website Bugfix 1h", projects: list)
        #expect(bugfix.projectId == website.id)
        #expect(bugfix.note == "Bugfix")
        let noteBefore = try entry("Kundenportal Review 9-10")
        #expect(noteBefore.projectId == portal.id)
        #expect(noteBefore.note == "Review")
    }

    // MARK: Zeiten und Tage

    @Test("Über Mitternacht: plausibel unter 12 h, ohne Tag die letzte Nacht")
    func overnight() throws {
        let lastNight = try entry("Garten 23:00-1:00")
        #expect(lastNight.start == date(2026, 10, 19, 23))
        #expect(lastNight.end == date(2026, 10, 20, 1))

        let explicit = try entry("Garten gestern 22-2")
        #expect(explicit.start == date(2026, 10, 19, 22))
        #expect(explicit.end == date(2026, 10, 20, 2))

        #expect(error("Garten 9-8") == .invalidTimeRange)
        #expect(error("Garten 20-9") == .invalidTimeRange)   // 13 h
        #expect(error("Garten 9-9") == .invalidTimeRange)
    }

    @Test("Schreibweisen: Punkt, Leerzeichen um den Strich, Uhr, von … bis, 24:00")
    func spellings() throws {
        let dotted = try entry("Kundenportal 9.30 - 11 Uhr #Review")
        #expect(dotted.start == date(2026, 10, 20, 9, 30))
        #expect(dotted.end == date(2026, 10, 20, 11))
        #expect(dotted.tag == "Review")
        #expect(dotted.note == nil)

        let fromTo = try entry("Garten von 8 bis 9:45 Uhr Hecke schneiden")
        #expect(fromTo.start == date(2026, 10, 20, 8))
        #expect(fromTo.end == date(2026, 10, 20, 9, 45))
        #expect(fromTo.note == "Hecke schneiden")

        let dash = try entry("Garten 9:00 – 10:00")
        #expect(dash.end == date(2026, 10, 20, 10))

        let midnight = try entry("Steuer 22-24:00")
        #expect(midnight.end == date(2026, 10, 21))
    }

    @Test("Tage: Datum, heutiger Wochentag, vorgestern")
    func days() throws {
        #expect(try entry("19.10. 9-10 Garten").start == date(2026, 10, 19, 9))
        #expect(try entry("Garten 1.10.2026 9-10").start == date(2026, 10, 1, 9))
        #expect(try entry("Di 9-10 Garten").start == date(2026, 10, 20, 9))        // heute ist Dienstag
        #expect(try entry("Mittwoch 9-10 Garten").start == date(2026, 10, 14, 9))  // letzter Mittwoch
        #expect(try entry("Garten vorgestern 9-10").start == date(2026, 10, 18, 9))
        #expect(try entry("Garten 9-10 gestern Rasen").start == date(2026, 10, 19, 9))
        #expect(try entry("24.12. 9-10 Garten").start == date(2025, 12, 24, 9))    // ohne Jahr: nicht in der Zukunft
    }

    @Test("Bloßer Start: Timer seit …")
    func backdatedStart() throws {
        let since = try entry("Website seit 9:30")
        #expect(since.isRunningStart)
        #expect(since.start == date(2026, 10, 20, 9, 30))
        #expect(since.end == nil)
        #expect(try entry("Website 14:15 Deploy").start == date(2026, 10, 20, 14, 15))
        #expect(error("Website 22:00") == .startInFuture)
        // Kurz nach Mitternacht meint „seit 23:00“ den Vorabend.
        #expect(try entry("Website seit 23:00", now: date(2026, 10, 21, 0, 30)).start == date(2026, 10, 20, 23))
        // Zahlen ohne Doppelpunkt bleiben Text
        let version = try entry("Website Release 1.20")
        #expect(version.isRunningStart)
        #expect(version.start == now)
        #expect(version.note == "Release 1.20")
    }

    @Test("Fehler: leer, ohne Projekt, anderer Tag ohne Zeiten")
    func errors() {
        #expect(error("") == .empty)
        #expect(error("   ") == .empty)
        #expect(error("9-10") == .missingProject)
        #expect(error("#meeting 1h") == .missingProject)
        #expect(error("gestern Website") == .missingTime)
        #expect(error("gestern Website 2h") == .missingTime)
        #expect(QuickEntryError.ambiguousProject([website, webshop]).errorDescription == "Mehrere Projekte passen: Website, Webshop.")
    }

    @Test("Ein Projekt namens wie ein Wochentag bleibt erreichbar")
    func weekdayProject() throws {
        let sunday = Project(name: "Sonntag", colorHex: "#007AFF")
        let e = try entry("Sonntag", projects: [sunday])
        #expect(e.projectId == sunday.id)
        #expect(e.isRunningStart)
    }

    @Test("Tag wird gekürzt; nur das erste #Wort ist der Tag")
    func tagRules() throws {
        let long = String(repeating: "a", count: 50)
        let e = try entry("Garten 1h #\(long) #zweiter Rest")
        #expect(e.tag?.count == 40)
        #expect(e.note == "#zweiter Rest")
    }
}
