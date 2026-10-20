import Foundation
import Testing
@testable import TaktCore

/// Deutscher Kalender (Montag als Wochenbeginn, ISO-KW) in Berlin.
let deCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "de_DE")
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return calendar
}()

@Suite("Berichtszeitraum")
struct ReportPeriodTests {
    @Test("Tag: Mitternacht bis Mitternacht, Titel ausgeschrieben")
    func day() {
        let period = ReportPeriod.day(date(2026, 10, 20, 15, 30))
        #expect(period.interval(calendar: deCalendar) == DateInterval(start: date(2026, 10, 20), end: date(2026, 10, 21)))
        #expect(period.title(calendar: deCalendar) == "Dienstag, 20. Oktober 2026")
        #expect(period.previous(calendar: deCalendar).interval(calendar: deCalendar).start == date(2026, 10, 19))
        #expect(period.next(calendar: deCalendar).title(calendar: deCalendar) == "Mittwoch, 21. Oktober 2026")
    }

    @Test("Woche: Montag bis Sonntag, auch mit Sonntag-Kalender; über die Zeitumstellung")
    func week() {
        let period = ReportPeriod.week(date(2026, 10, 20, 12))
        let expected = DateInterval(start: date(2026, 10, 19), end: date(2026, 10, 26))
        #expect(period.interval(calendar: deCalendar) == expected)
        // Kalender ohne Locale (Wochenbeginn Sonntag): trotzdem Montag
        #expect(period.interval(calendar: testCalendar) == expected)
        // Zeitumstellung am 25.10.: Woche ist eine Stunde länger
        #expect(expected.duration == 7 * 24 * hour + hour)
        #expect(period.title(calendar: deCalendar) == "KW 43 · 19.–25. Okt. 2026")
        // Sonntag gehört zur Woche davor
        #expect(ReportPeriod.week(date(2026, 10, 25, 22)).interval(calendar: deCalendar) == expected)
        #expect(ReportPeriod.week(date(2026, 10, 26)).interval(calendar: deCalendar).start == date(2026, 10, 26))
    }

    @Test("Woche: Titel über Monats- und Jahresgrenzen, vor/zurück")
    func weekTitles() {
        #expect(ReportPeriod.week(date(2026, 10, 28)).title(calendar: deCalendar) == "KW 44 · 26. Okt.–1. Nov. 2026")
        #expect(ReportPeriod.week(date(2026, 1, 1)).title(calendar: deCalendar) == "KW 1 · 29. Dez. 2025–4. Jan. 2026")
        let week = ReportPeriod.week(date(2026, 10, 20))
        #expect(week.next(calendar: deCalendar).title(calendar: deCalendar) == "KW 44 · 26. Okt.–1. Nov. 2026")
        #expect(week.previous(calendar: deCalendar).title(calendar: deCalendar) == "KW 42 · 12.–18. Okt. 2026")
    }

    @Test("Monat: ganzer Kalendermonat, vor/zurück auch vom 31.")
    func month() {
        let period = ReportPeriod.month(date(2026, 10, 31, 23))
        #expect(period.interval(calendar: deCalendar) == DateInterval(start: date(2026, 10, 1), end: date(2026, 11, 1)))
        #expect(period.title(calendar: deCalendar) == "Oktober 2026")
        #expect(period.next(calendar: deCalendar).title(calendar: deCalendar) == "November 2026")
        #expect(period.previous(calendar: deCalendar).title(calendar: deCalendar) == "September 2026")
        #expect(ReportPeriod.month(date(2026, 3, 15)).title(calendar: deCalendar) == "März 2026")
        #expect(ReportPeriod.month(date(2026, 1, 5)).previous(calendar: deCalendar).title(calendar: deCalendar) == "Dezember 2025")
    }

    @Test("Frei: Titel als Tagesspanne, Verschieben um die eigene Länge")
    func custom() {
        let interval = DateInterval(start: date(2026, 10, 1), end: date(2026, 10, 16))
        let period = ReportPeriod.custom(interval)
        #expect(period.interval(calendar: deCalendar) == interval)
        #expect(period.title(calendar: deCalendar) == "1.–15. Okt. 2026")
        #expect(period.next(calendar: deCalendar) == .custom(DateInterval(start: date(2026, 10, 16), end: date(2026, 10, 31))))
        #expect(period.previous(calendar: deCalendar) == .custom(DateInterval(start: date(2026, 9, 16), end: date(2026, 10, 1))))
        #expect(ReportPeriod.custom(DateInterval(start: date(2026, 10, 15), end: date(2026, 10, 16))).title(calendar: deCalendar) == "15. Okt. 2026")
    }
}

@Suite("Rundung")
struct RoundingTests {
    @Test("Aufrunden auf die Schrittweite", arguments: roundingCases)
    func apply(rounding: Rounding, input: TimeInterval, expected: TimeInterval) {
        #expect(rounding.apply(input) == expected)
    }

    @Test("Rohwerte sind stabil (Einstellungen speichern sie)")
    func rawValues() {
        #expect(Rounding.allCases.map(\.rawValue) == ["none", "minutes6", "minutes15", "minutes30"])
    }
}

private let roundingCases: [(Rounding, TimeInterval, TimeInterval)] = [
    (.none, 0, 0),
    (.none, 61.5, 61.5),
    (.none, -5, 0),
    (.minutes6, 0, 0),
    (.minutes6, 1, 6 * minute),
    (.minutes6, 6 * minute, 6 * minute),
    (.minutes6, 6 * minute + 0.0000001, 6 * minute),  // Gleitkomma-Rauschen
    (.minutes6, 6 * minute + 1, 12 * minute),
    (.minutes15, 14 * minute, 15 * minute),
    (.minutes15, 61 * minute, 75 * minute),
    (.minutes30, 31 * minute, 60 * minute),
    (.minutes30, 2 * hour, 2 * hour),
]

@Suite("Bericht")
struct BillingReportTests {
    /// Alpha: Business 80 €/h; Beta: Business ohne Satz; Gamma: Privat.
    private func fixture() throws -> Fixture {
        let f = try Fixture()
        var alpha = f.alpha
        alpha.hourlyRate = 80
        alpha.client = "ACME"
        try f.db.saveProject(alpha)
        return f
    }

    @Test("Summen, Business/Privat, Zeilen nach Dauer, Zuschnitt an den Grenzen, Laufendes bis now")
    func totals() throws {
        let f = try fixture()
        try f.entry(f.alpha, date(2026, 10, 19, 23), date(2026, 10, 20, 1))    // 1 h am 20.
        try f.entry(f.beta, date(2026, 10, 20, 9), date(2026, 10, 20, 12))     // 3 h
        try f.entry(f.gamma, date(2026, 10, 20, 13), date(2026, 10, 20, 13, 30)) // 0,5 h
        try f.db.startTimer(projectId: f.alpha.id, now: date(2026, 10, 20, 15))  // läuft, 1 h bis now

        let report = try f.db.report(
            for: .day(date(2026, 10, 20)), rounding: .none, now: date(2026, 10, 20, 16), calendar: deCalendar
        )
        #expect(report.total == 5.5 * hour)
        #expect(report.business == 5 * hour)
        #expect(report.personal == 0.5 * hour)
        #expect(report.billable == 5 * hour)
        #expect(report.rows.map(\.project.name) == ["Beta", "Alpha", "Gamma"])
        #expect(report.rows.map(\.duration) == [3 * hour, 2 * hour, 0.5 * hour])
        #expect(report.rows.map(\.entryCount) == [1, 2, 1])
        #expect(report.days.count == 1)
        #expect(report.activeDays == 1)
        #expect(report.averagePerActiveDay == 5.5 * hour)
        #expect(report.focus.switches == 3)
    }

    @Test("Rundung je Eintrag und Umsatz: nur abrechenbare Zeit mit Satz")
    func roundingAndAmount() throws {
        let f = try fixture()
        // Alpha (80 €/h): 7 min + 50 min → 15 + 60 = 75 min gerundet; 20 min nicht abrechenbar
        try f.entry(f.alpha, date(2026, 10, 20, 9), date(2026, 10, 20, 9, 7))
        try f.entry(f.alpha, date(2026, 10, 20, 10), date(2026, 10, 20, 10, 50))
        try f.db.addEntry(TimeEntry(
            projectId: f.alpha.id, startedAt: date(2026, 10, 20, 11), endedAt: date(2026, 10, 20, 11, 20), isBillable: false
        ))
        // Beta (Business, ohne Satz): 1 h
        try f.entry(f.beta, date(2026, 10, 20, 12), date(2026, 10, 20, 13))
        // Gamma (Privat), aber Eintrag ausdrücklich abrechenbar: 10 min
        try f.db.addEntry(TimeEntry(
            projectId: f.gamma.id, startedAt: date(2026, 10, 20, 14), endedAt: date(2026, 10, 20, 14, 10), isBillable: true
        ))

        let report = try f.db.report(
            for: .day(date(2026, 10, 20)), rounding: .minutes15, now: date(2026, 10, 21), calendar: deCalendar
        )
        let alpha = try #require(report.rows.first { $0.project.id == f.alpha.id })
        #expect(alpha.duration == 77 * minute)
        #expect(alpha.roundedDuration == (15 + 60 + 30) * minute)
        #expect(alpha.billableDuration == 57 * minute)
        #expect(alpha.roundedBillableDuration == 75 * minute)
        #expect(alpha.hourlyRate == 80)
        #expect(alpha.amount == 100)  // 1,25 h × 80 €

        let beta = try #require(report.rows.first { $0.project.id == f.beta.id })
        #expect(beta.amount == nil)
        #expect(beta.roundedBillableDuration == 1 * hour)

        let gamma = try #require(report.rows.first { $0.project.id == f.gamma.id })
        #expect(gamma.billableDuration == 10 * minute)
        #expect(gamma.roundedBillableDuration == 15 * minute)

        #expect(report.amount == 100)
        #expect(report.billable == (57 + 60 + 10) * minute)
        #expect(report.roundedBillable == (75 + 60 + 15) * minute)
        #expect(report.roundedTotal == (105 + 60 + 15) * minute)
    }

    @Test("Standard-Stundensatz gilt für Projekte ohne eigenen Satz; Cent-Rundung")
    func defaultRate() throws {
        let f = try fixture()
        try f.entry(f.alpha, date(2026, 10, 20, 9), date(2026, 10, 20, 9, 10))  // 10 min × 80 €/h
        try f.entry(f.beta, date(2026, 10, 20, 10), date(2026, 10, 20, 10, 20)) // 20 min × 95,50 €/h

        let report = try f.db.report(
            for: .day(date(2026, 10, 20)), rounding: .none, defaultHourlyRate: Decimal(string: "95.5")!,
            now: date(2026, 10, 21), calendar: deCalendar
        )
        let alpha = try #require(report.rows.first { $0.project.id == f.alpha.id })
        let beta = try #require(report.rows.first { $0.project.id == f.beta.id })
        #expect(alpha.amount == Decimal(string: "13.33")!)   // 13,333… → 13,33
        #expect(beta.hourlyRate == Decimal(string: "95.5")!)
        #expect(beta.amount == Decimal(string: "31.83")!)    // 31,8333… → 31,83
        #expect(report.amount == Decimal(string: "45.16")!)
    }

    @Test("Tages-Buckets: lückenlos über die Woche, Einträge über Mitternacht anteilig")
    func dayBuckets() throws {
        let f = try fixture()
        try f.entry(f.alpha, date(2026, 10, 19, 9), date(2026, 10, 19, 11))     // Mo 2 h
        try f.entry(f.beta, date(2026, 10, 21, 23), date(2026, 10, 22, 1))      // Mi 1 h, Do 1 h
        try f.entry(f.gamma, date(2026, 10, 25, 10), date(2026, 10, 25, 10, 30)) // So 0,5 h
        try f.entry(f.alpha, date(2026, 10, 26, 9), date(2026, 10, 26, 10))     // nächste Woche

        let report = try f.db.report(
            for: .week(date(2026, 10, 20)), rounding: .none, now: date(2026, 11, 1), calendar: deCalendar
        )
        #expect(report.days.count == 7)
        #expect(report.days.map(\.day) == (19...25).map { date(2026, 10, $0) })
        #expect(report.days[0].perProject == [f.alpha.id: 2 * hour])
        #expect(report.days[1].perProject.isEmpty)
        #expect(report.days[2].perProject == [f.beta.id: 1 * hour])
        #expect(report.days[3].perProject == [f.beta.id: 1 * hour])
        #expect(report.days[6].perProject == [f.gamma.id: 30 * minute])
        #expect(report.days.map(\.total).reduce(0, +) == report.total)
        #expect(report.total == 4.5 * hour)
        #expect(report.activeDays == 4)
        #expect(report.averagePerActiveDay == 4.5 * hour / 4)
    }

    @Test("Monat: ein Bucket je Tag; leerer Zeitraum ergibt Nullen")
    func monthAndEmpty() throws {
        let f = try fixture()
        let report = try f.db.report(
            for: .month(date(2026, 2, 10)), rounding: .minutes6, now: date(2026, 10, 20), calendar: deCalendar
        )
        #expect(report.days.count == 28)
        #expect(report.total == 0)
        #expect(report.rows.isEmpty)
        #expect(report.amount == 0)
        #expect(report.activeDays == 0)
        #expect(report.averagePerActiveDay == 0)
        #expect(report.focus == FocusStats(switches: 0, longestBlock: 0))
    }

    @Test("Money: Formatierung und Eingabe")
    func money() {
        #expect(Money.germanString(85) == "85,00")
        #expect(Money.germanString(Decimal(string: "1234.5")!) == "1234,50")
        #expect(Money.germanString(Decimal(string: "0.005")!) == "0,01")
        #expect(Money.germanString(Decimal(string: "-3.1")!) == "-3,10")
        #expect(Money.parse("85") == 85)
        #expect(Money.parse("85,5") == Decimal(string: "85.5"))
        #expect(Money.parse("85.50 €") == Decimal(string: "85.5"))
        #expect(Money.parse("1.234,50") == Decimal(string: "1234.5"))
        #expect(Money.parse("") == nil)
        #expect(Money.parse("abc") == nil)
        #expect(Money.parse("1.2.3") == nil)
    }
}
