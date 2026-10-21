import Foundation
import SwiftUI
import TaktCore

// Daten und Formate der Ansicht „Berichte“. Ohne Store-Abhängigkeit: `ReportsView` befüllt
// `ReportsData` aus `TaktStore` und `AppSettings`, das Render-Harness aus einer Beispiel-Datenbank.

// MARK: - Art des Zeitraums

/// Auswahl im Segment „Tag · Woche · Monat · Jahr · Zeitraum“. Das Jahr gibt es nur in der
/// Oberfläche (`ReportPeriod` kennt es nicht); `ReportsHeader` führt es als eigene Auswahl.
enum ReportPeriodKind: String, CaseIterable, Identifiable {
    case day, week, month, year, custom

    var id: Self { self }

    var title: String {
        switch self {
        case .day: "Tag"
        case .week: "Woche"
        case .month: "Monat"
        case .year: "Jahr"
        case .custom: "Zeitraum"
        }
    }

    init(_ period: ReportPeriod) {
        switch period {
        case .day: self = .day
        case .week: self = .week
        case .month: self = .month
        case .custom: self = .custom
        }
    }

    /// Wechselt die Art und behält dabei den Bezug: Enthält der bisherige Zeitraum heute,
    /// geht es um heute, sonst um seinen Anfang. „Zeitraum“ übernimmt das bisherige Intervall.
    func period(from current: ReportPeriod, now: Date, calendar: Calendar) -> ReportPeriod {
        let interval = current.interval(calendar: calendar)
        let anchor = interval.contains(now) ? now : interval.start
        switch self {
        case .day: return .day(anchor)
        case .week: return .week(anchor)
        case .month: return .month(anchor)
        // Das Jahr steuert `ReportsHeader` selbst; hier bleibt der bisherige Zeitraum.
        case .year: return current
        case .custom:
            if case .custom = current { return current }
            return .custom(interval)
        }
    }
}

// MARK: - Daten

struct ReportsData {
    var report: Report
    /// Einträge, die sich mit dem Zeitraum überschneiden, nach Start sortiert.
    var entries: [TimeEntry]
    var rounding: Rounding
    var currencyCode: String
    var now: Date
    var calendar: Calendar = .current

    var interval: DateInterval { report.interval }
    var isEmpty: Bool { report.rows.isEmpty }
    var hasRunningEntry: Bool { entries.contains(where: \.isRunning) }

    /// Mindestens eine Projektzeile hat einen Stundensatz (sonst gibt es keinen Umsatz).
    var hasAnyRate: Bool { report.rows.contains { $0.hourlyRate != nil } }

    /// Kachel „Effektiver Satz“ nur in Woche und Monat (ein Tag ist zu kurz für eine Aussage,
    /// der Jahresbericht hat eigene Kennzahlen).
    var showsRateTile: Bool {
        switch report.period {
        case .week, .month: true
        case .day, .custom: false
        }
    }

    /// Projekte mit abrechenbarer Zeit, aber ohne Stundensatz.
    var billableRowsWithoutRate: [ProjectReportRow] {
        report.rows.filter { $0.hourlyRate == nil && $0.roundedBillableDuration > 0 }
    }

    /// Freie Tage im Zeitraum nach Tagesbeginn (für das Diagramm).
    var daysOffByDay: [Date: DayOff] {
        var result: [Date: DayOff] = [:]
        for dayOff in report.daysOff {
            if let day = dayOff.startOfDay(calendar: calendar) { result[day] = dayOff }
        }
        return result
    }

    /// Mindestens ein Eintrag des Projekts hat ein Tag (sonst lohnt die Aufschlüsselung nicht).
    func hasTags(_ row: ProjectReportRow) -> Bool {
        row.byTag.contains { $0.tag != nil }
    }

    /// Einträge eines Projekts im Zeitraum, chronologisch.
    func entries(for projectId: UUID) -> [TimeEntry] {
        entries.filter { $0.projectId == projectId }
    }

    /// Dauer eines Eintrags innerhalb des Zeitraums (laufende bis jetzt).
    func clippedDuration(_ entry: TimeEntry) -> TimeInterval {
        let start = max(entry.startedAt, interval.start)
        let end = max(start, min(entry.endedAt ?? now, interval.end))
        return end.timeIntervalSince(start)
    }

    // MARK: Diagramm

    /// Granularität des Diagramms: Stunden beim Tag, Tage bis gut zwei Monate, sonst Wochen.
    enum ChartUnit {
        case hour, day, week

        var component: Calendar.Component {
            switch self {
            case .hour: .hour
            case .day: .day
            case .week: .weekOfYear
            }
        }
    }

    var chartUnit: ChartUnit {
        if case .day = report.period { return .hour }
        return report.days.count > 62 ? .week : .day
    }

    /// Ein Balken des Diagramms.
    struct ChartBucket: Identifiable, Hashable {
        var start: Date
        var end: Date
        var perProject: [UUID: TimeInterval]

        var id: Date { start }
        var total: TimeInterval { perProject.values.reduce(0, +) }
    }

    /// Kalender für Wochen-Balken: Montag als Wochenbeginn, KW nach ISO 8601.
    var isoCalendar: Calendar {
        var iso = calendar
        iso.firstWeekday = 2
        iso.minimumDaysInFirstWeek = 4
        return iso
    }

    /// Balken des Diagramms, lückenlos und aufsteigend.
    var chartBuckets: [ChartBucket] {
        switch chartUnit {
        case .day:
            return report.days.map { day in
                let end = calendar.date(byAdding: .day, value: 1, to: day.day) ?? day.day.addingTimeInterval(86_400)
                return ChartBucket(start: day.day, end: end, perProject: day.perProject)
            }
        case .week:
            var buckets: [ChartBucket] = []
            let iso = isoCalendar
            for day in report.days {
                let weekStart = iso.dateInterval(of: .weekOfYear, for: day.day)?.start ?? day.day
                if buckets.last?.start != weekStart {
                    let end = iso.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart.addingTimeInterval(7 * 86_400)
                    buckets.append(ChartBucket(start: weekStart, end: end, perProject: [:]))
                }
                for (id, seconds) in day.perProject {
                    buckets[buckets.count - 1].perProject[id, default: 0] += seconds
                }
            }
            return buckets
        case .hour:
            let window = hourWindow
            let dayStart = calendar.startOfDay(for: interval.start)
            return window.dropLast().compactMap { hour -> ChartBucket? in
                guard let start = calendar.date(byAdding: .hour, value: hour, to: dayStart),
                      let end = calendar.date(byAdding: .hour, value: 1, to: start) else { return nil }
                var perProject: [UUID: TimeInterval] = [:]
                for entry in entries {
                    let s = max(entry.startedAt, start, interval.start)
                    let e = min(entry.endedAt ?? now, end, interval.end)
                    if e > s { perProject[entry.projectId, default: 0] += e.timeIntervalSince(s) }
                }
                return ChartBucket(start: start, end: end, perProject: perProject)
            }
        }
    }

    /// Sichtbare Stunden beim Tag: 8–19 Uhr, erweitert um Einträge außerhalb (wie „Heute“).
    var hourWindow: ClosedRange<Int> {
        var lower = 8
        var upper = 19
        let dayStart = calendar.startOfDay(for: interval.start)
        for entry in entries {
            let start = max(entry.startedAt, interval.start)
            let end = min(entry.endedAt ?? now, interval.end)
            guard end > start else { continue }
            lower = min(lower, Int((start.timeIntervalSince(dayStart) / 3600).rounded(.down)))
            upper = max(upper, Int((end.timeIntervalSince(dayStart) / 3600).rounded(.up)))
        }
        lower = max(0, lower)
        upper = min(24, max(upper, lower + 1))
        return lower...upper
    }
}

/// Aktionen der Berichte-Ansicht; `ReportsView` verdrahtet sie mit Export und Import.
struct ReportsActions {
    var exportEntries: () -> Void = {}
    var exportSummary: () -> Void = {}
    /// Reiter „Jahr“: Monatszeilen und Kundentabelle als CSV.
    var exportYear: () -> Void = {}
    /// Öffnet „Timesheet als PDF“ für den gezeigten Zeitraum.
    var exportTimesheet: () -> Void = {}
    var importToggl: () -> Void = {}
    /// Öffnet „Freie Tage“ für den gewählten Zeitraum.
    var editDaysOff: () -> Void = {}
}

// MARK: - Formate

enum ReportsFormat {
    static let weekdaysShort = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
    static let monthsShort = ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni",
                              "Juli", "Aug.", "Sept.", "Okt.", "Nov.", "Dez."]

    /// `h:mm`, abgerundet (wie überall in der App).
    static func duration(_ seconds: TimeInterval) -> String {
        DurationFormat.hourMinute(seconds)
    }

    /// „1240,00“ – Dezimalkomma, zwei Stellen.
    static func money(_ value: Decimal) -> String {
        Money.germanString(value)
    }

    /// „09:05“
    static func clock(_ date: Date) -> String {
        ClockFormat.time(date)
    }

    /// „Mo 19.10.“
    static func shortDay(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.weekday, .day, .month], from: date)
        return String(format: "%@ %d.%d.", weekdaysShort[(c.weekday ?? 1) - 1], c.day ?? 0, c.month ?? 0)
    }

    /// „Mittwoch, 21. Okt.“ – für den Tooltip im Diagramm.
    static func tooltipDay(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.weekday, .day, .month], from: date)
        let weekdays = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
        return "\(weekdays[(c.weekday ?? 1) - 1]), \(c.day ?? 0). \(monthsShort[(c.month ?? 1) - 1])"
    }

    /// „4 Arbeitstage“, „1 Arbeitstag“, „kein Arbeitstag“.
    static func workdays(_ count: Int) -> String {
        switch count {
        case 0: "kein Arbeitstag"
        case 1: "1 Arbeitstag"
        default: "\(count) Arbeitstage"
        }
    }

    /// Prozent ohne Nachkommastellen, „80 %“.
    static func percent(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "–" }
        return "\(Int((fraction * 100).rounded())) %"
    }

    /// Hinweis zur Rundung unter der abrechenbaren Zeit.
    static func roundingHint(_ rounding: Rounding) -> String {
        switch rounding {
        case .none: "ungerundet"
        case .minutes6: "auf 6 Min aufgerundet"
        case .minutes15: "auf 15 Min aufgerundet"
        case .minutes30: "auf 30 Min aufgerundet"
        }
    }
}
