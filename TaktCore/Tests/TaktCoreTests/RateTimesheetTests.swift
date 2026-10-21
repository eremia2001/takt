import Foundation
import Testing
@testable import TaktCore

@Suite("Effektiver Stundensatz")
struct EffectiveRateTests {
    @Test("Money.rate: Betrag je Stunde, auf Cent; nil ohne Betrag oder Zeit")
    func moneyRate() {
        #expect(Money.rate(amount: 950, seconds: 10 * hour) == 95)
        #expect(Money.rate(amount: 100, seconds: 3 * hour) == Decimal(string: "33.33"))
        #expect(Money.rate(amount: 200, seconds: 3 * hour) == Decimal(string: "66.67"))
        #expect(Money.rate(amount: 0, seconds: hour) == nil)
        #expect(Money.rate(amount: 50, seconds: 0) == nil)
        #expect(Money.rate(amount: 50, seconds: .infinity) == nil)
    }

    /// Alpha: 95 €/h, 8 h abrechenbar + 2 h nicht abrechenbar (Akquise). Beta: Business ohne Satz,
    /// 2 h nicht abrechenbar (Projekt nicht abrechenbar). Gamma: privat, 5 h.
    private func fixture() throws -> (Fixture, Project, Project) {
        let f = try Fixture()
        var alpha = f.alpha
        alpha.hourlyRate = 95
        alpha.client = "ACME"
        try f.db.saveProject(alpha)
        var beta = f.beta
        beta.isBillable = false
        beta.client = "acme "
        try f.db.saveProject(beta)
        try f.entry(alpha, date(2026, 10, 19, 9), date(2026, 10, 19, 17))                      // 8 h
        try f.db.addEntry(TimeEntry(projectId: alpha.id, startedAt: date(2026, 10, 20, 9),
                                    endedAt: date(2026, 10, 20, 11), isBillable: false))          // 2 h n. abr.
        try f.entry(beta, date(2026, 10, 21, 9), date(2026, 10, 21, 11))                       // 2 h
        try f.entry(f.gamma, date(2026, 10, 24, 9), date(2026, 10, 24, 14))                    // 5 h privat
        return (f, alpha, beta)
    }

    @Test("Projektzeile: Betrag ÷ gesamte Projektzeit inkl. nicht abrechenbar")
    func projectRow() throws {
        let (f, alpha, beta) = try fixture()
        let report = try f.db.report(for: .week(date(2026, 10, 20)), rounding: .none, now: date(2026, 10, 25), calendar: testCalendar)
        let a = try #require(report.rows.first { $0.project.id == alpha.id })
        #expect(a.amount == 760)                // 8 h × 95
        #expect(a.effectiveRate == 76)          // 760 / 10 h
        // 76 liegt 20 % unter 95: unter der 15-%-Schwelle, aber nicht unter einer 25-%-Schwelle.
        #expect(a.isEffectiveRateLow(threshold: 0.15))
        #expect(!a.isEffectiveRateLow(threshold: 0.25))
        let b = try #require(report.rows.first { $0.project.id == beta.id })
        #expect(b.amount == nil)
        #expect(b.effectiveRate == nil)
        #expect(!b.isEffectiveRateLow())
        let g = try #require(report.rows.first { $0.project.id == f.gamma.id })
        #expect(g.effectiveRate == nil)
    }

    @Test("Bericht: Betrag ÷ Business-Zeit, nominaler Satz, Anteil nicht abrechenbar")
    func report() throws {
        let (f, _, _) = try fixture()
        let report = try f.db.report(for: .week(date(2026, 10, 20)), rounding: .none, now: date(2026, 10, 25), calendar: testCalendar)
        #expect(report.business == 12 * hour)
        #expect(report.amount == 760)
        #expect(report.effectiveRate == Decimal(string: "63.33"))   // 760 / 12 h, Privatzeit ausgenommen
        #expect(report.nominalRate == 95)
        #expect(abs(report.nonBillableShare - 4.0 / 12.0) < 1e-9)
        #expect(report.isEffectiveRateLow())
    }

    @Test("Nominal mit Rundung und Standardsatz; Projekte ohne Satz drücken den Schnitt nicht")
    func nominalWithRounding() throws {
        let f = try Fixture()
        var alpha = f.alpha
        alpha.hourlyRate = 100
        try f.db.saveProject(alpha)
        try f.entry(alpha, date(2026, 10, 19, 9), date(2026, 10, 19, 9, 50))   // 50 min → 1 h = 100
        try f.entry(f.beta, date(2026, 10, 20, 9), date(2026, 10, 20, 10))      // 1 h, kein Satz
        let none = try f.db.report(for: .week(date(2026, 10, 20)), rounding: .minutes30, now: date(2026, 10, 25), calendar: testCalendar)
        #expect(none.amount == 100)
        #expect(none.nominalRate == 100)
        #expect(none.effectiveRate == Decimal(string: "54.55"))      // 100 / (110 min)
        #expect(none.nonBillableShare == 0)

        let withDefault = try f.db.report(for: .week(date(2026, 10, 20)), rounding: .minutes30, defaultHourlyRate: 50,
                                          now: date(2026, 10, 25), calendar: testCalendar)
        #expect(withDefault.amount == 150)
        #expect(withDefault.nominalRate == 75)                        // 150 / 2 h gerundet
        #expect(withDefault.effectiveRate == Decimal(string: "81.82"))  // 150 / 110 min
        #expect(!withDefault.isEffectiveRateLow())
    }

    @Test("Leerer Bericht: nil und 0")
    func empty() throws {
        let f = try Fixture()
        let report = try f.db.report(for: .week(date(2026, 10, 20)), rounding: .none, now: date(2026, 10, 25), calendar: testCalendar)
        #expect(report.effectiveRate == nil)
        #expect(report.nominalRate == nil)
        #expect(report.nonBillableShare == 0)
        #expect(!report.isEffectiveRateLow())
    }

    @Test("Jahr und Kunden: effektiver Satz über die gesamte Zeit")
    func year() throws {
        let (f, _, _) = try fixture()
        let year = try f.db.yearReport(year: 2026, rounding: .none, now: date(2026, 10, 25), calendar: testCalendar)
        #expect(year.effectiveRate == Decimal(string: "63.33"))
        #expect(year.nominalRate == 95)
        #expect(abs(year.nonBillableShare - 4.0 / 12.0) < 1e-9)
        #expect(year.isEffectiveRateLow())
        let acme = try #require(year.byClient.first)
        #expect(acme.client == "ACME")
        #expect(acme.duration == 12 * hour)
        #expect(acme.effectiveRate == Decimal(string: "63.33"))
        let personal = try #require(year.byClient.first { $0.client == nil })
        #expect(personal.effectiveRate == nil)
    }
}

@Suite("Timesheet")
struct TimesheetTests {
    /// Müller: Portal (95 €/h) und Shop (Standardsatz); Studio: Website (70 €/h); Privat: Gamma.
    private struct Data {
        let portal = Project(name: "Portal", colorHex: "#007AFF", sortOrder: 0, client: "Müller GmbH", hourlyRate: 95)
        let shop = Project(name: "Shop", colorHex: "#5856D6", sortOrder: 1, client: " müller gmbh")
        let website = Project(name: "Website", colorHex: "#30B0C7", sortOrder: 2, client: "Studio Nord", hourlyRate: 70)
        let garden = Project(name: "Garten", colorHex: "#34C759", isBusiness: false, sortOrder: 3)
        var projects: [Project] { [portal, shop, website, garden] }
        let october = DateInterval(start: date(2026, 10, 1), end: date(2026, 11, 1))

        var entries: [TimeEntry] {
            [
                TimeEntry(projectId: portal.id, startedAt: date(2026, 10, 5, 9), endedAt: date(2026, 10, 5, 10, 10),
                          nextStep: "  Login-Flow  ", tag: "Entwicklung"),                                      // 70 min
                TimeEntry(projectId: portal.id, startedAt: date(2026, 10, 5, 14), endedAt: date(2026, 10, 5, 14, 20),
                          isBillable: false, tag: "Akquise"),                                                   // 20 min n. abr.
                TimeEntry(projectId: shop.id, startedAt: date(2026, 10, 6, 9), endedAt: date(2026, 10, 6, 11)),  // 2 h
                TimeEntry(projectId: website.id, startedAt: date(2026, 10, 6, 13), endedAt: date(2026, 10, 6, 14)), // 1 h
                TimeEntry(projectId: garden.id, startedAt: date(2026, 10, 10, 10), endedAt: date(2026, 10, 10, 12)),
                // Über die Monatsgrenze: nur 30 min im Oktober.
                TimeEntry(projectId: portal.id, startedAt: date(2026, 9, 30, 23, 30), endedAt: date(2026, 10, 1, 0, 30),
                          nextStep: "   "),
                // Laufend: nie im Nachweis.
                TimeEntry(projectId: portal.id, startedAt: date(2026, 10, 21, 9)),
            ]
        }
    }

    @Test("Kunde: zusammengefasste Schreibweise, Rundung je Eintrag, Satz je Projekt oder Standard")
    func client() {
        let d = Data()
        let sheet = Timesheet.make(
            entries: d.entries, projects: d.projects, interval: d.october, scope: .client("MÜLLER GMBH"),
            options: TimesheetOptions(billableOnly: true, rounding: .minutes15),
            defaultHourlyRate: 80, calendar: testCalendar
        )
        #expect(sheet.lines.map(\.project.name) == ["Portal", "Portal", "Shop"])
        #expect(sheet.lines[0].start == date(2026, 10, 1))                // zugeschnitten
        #expect(sheet.lines[0].duration == 30 * minute)
        #expect(sheet.lines[0].note == nil)                               // nur Leerzeichen
        #expect(sheet.lines[1].note == "Login-Flow")
        #expect(sheet.lines[1].tag == "Entwicklung")
        #expect(sheet.lines[1].billedDuration == 75 * minute)
        #expect(sheet.lines[1].amount == Decimal(string: "118.75"))       // 1,25 h × 95
        #expect(sheet.lines[2].hourlyRate == 80)
        #expect(sheet.lines[2].amount == 160)
        #expect(sheet.days.map(\.day) == [date(2026, 10, 1), date(2026, 10, 5), date(2026, 10, 6)])
        #expect(sheet.days[1].billedDuration == 75 * minute)
        #expect(sheet.totalDuration == 30 * minute + 70 * minute + 2 * hour)
        #expect(sheet.totalBilledDuration == 30 * minute + 75 * minute + 2 * hour)
        #expect(sheet.rateGroups.map(\.rate) == [95, 80])
        #expect(sheet.rateGroups[0].billedDuration == 105 * minute)
        #expect(sheet.rateGroups[0].amount == Decimal(string: "166.25"))  // 47,50 + 118,75
        #expect(sheet.amount == Decimal(string: "326.25"))
        #expect(sheet.hourlyRate == nil)                                  // zwei Sätze
        #expect(sheet.excludedRunning.count == 1)
        #expect(!sheet.hasNonBillable)
        #expect(sheet.hasSeveralProjects)
        #expect(sheet.periodTitle(calendar: testCalendar) == "Oktober 2026")
    }

    @Test("Projekt ohne Rundung, mit nicht abrechenbaren Einträgen")
    func projectWithNonBillable() {
        let d = Data()
        let sheet = Timesheet.make(
            entries: d.entries, projects: d.projects, interval: d.october, scope: .project(d.portal.id),
            options: TimesheetOptions(billableOnly: false, rounding: .none),
            defaultHourlyRate: nil, calendar: testCalendar
        )
        #expect(sheet.lines.count == 3)
        #expect(sheet.hasNonBillable)
        #expect(sheet.lines[2].isBillable == false)
        #expect(sheet.lines[2].amount == nil)
        #expect(sheet.billableBilledDuration == 100 * minute)
        #expect(sheet.totalBilledDuration == 120 * minute)
        #expect(sheet.hourlyRate == 95)
        #expect(sheet.amount == Decimal(string: "158.33"))                // 47,50 + 110,83
        #expect(!sheet.hasSeveralProjects)
    }

    @Test("Alle Projekte, Teilzeitraum, ohne Satz: kein Betrag")
    func allWithoutRate() {
        let d = Data()
        let interval = DateInterval(start: date(2026, 10, 6), end: date(2026, 10, 16))
        var projects = d.projects
        projects[1].isBillable = false
        let sheet = Timesheet.make(
            entries: d.entries, projects: projects.map { var p = $0; p.hourlyRate = nil; return p },
            interval: interval, scope: .all, options: TimesheetOptions(billableOnly: true, rounding: .none),
            defaultHourlyRate: nil, calendar: testCalendar
        )
        #expect(sheet.lines.map(\.project.name) == ["Website"])            // Shop nicht abrechenbar, Garten privat
        #expect(sheet.amount == nil)
        #expect(sheet.billableWithoutRate == hour)
        #expect(sheet.excludedRunning.isEmpty)                              // läuft außerhalb des Zeitraums
        #expect(sheet.periodTitle(calendar: testCalendar) == "6.–15. Okt. 2026")
    }

    @Test("Kundenliste: ohne Dubletten und Leerwerte, alphabetisch")
    func clients() {
        let d = Data()
        let extra = Project(name: "X", colorHex: "#000000", client: "  ")
        #expect(Timesheet.clients(of: d.projects + [extra]) == ["Müller GmbH", "Studio Nord"])
        #expect(Timesheet.matches(d.shop, scope: .client("Muller GmbH")))
        #expect(!Timesheet.matches(d.garden, scope: .client("Müller GmbH")))
    }
}
