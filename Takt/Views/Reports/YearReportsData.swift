import Foundation
import SwiftUI
import TaktCore

// Daten des Berichts-Reiters „Jahr“. Ohne Store-Abhängigkeit: `ReportsView` befüllt
// `YearReportsData` aus `TaktStore.yearReport(…)` und den Einträgen des Jahres, das
// Render-Harness aus einer Beispiel-Datenbank.

struct YearReportsData {
    var report: YearReport
    /// Ungerundete Zeit je Projekt und Monat (Index 0 = Januar), laufende Einträge bis `now`.
    var projectMonths: [UUID: [TimeInterval]]
    var rounding: Rounding
    var currencyCode: String
    var now: Date
    var calendar: Calendar

    /// - Parameter entries: Einträge, die sich mit dem Jahr überschneiden (für den Monatsverlauf je Projekt).
    init(
        report: YearReport,
        entries: [TimeEntry],
        rounding: Rounding,
        currencyCode: String,
        now: Date,
        calendar: Calendar = .current
    ) {
        self.report = report
        self.rounding = rounding
        self.currencyCode = currencyCode
        self.now = now
        self.calendar = calendar
        self.projectMonths = Self.projectMonths(
            entries: entries, months: report.months.map(\.month), yearEnd: report.interval.end, now: now
        )
    }

    var year: Int { report.year }
    var isEmpty: Bool { report.byProject.isEmpty }

    /// Mindestens eine Projektzeile hat einen Stundensatz (sonst gibt es keinen Umsatz).
    var hasAnyRate: Bool { report.byProject.contains { $0.hourlyRate != nil } }

    /// Abrechenbar, je Eintrag gerundet (wie `Report.roundedBillable`).
    var roundedBillable: TimeInterval { report.byProject.reduce(0) { $0 + $1.roundedBillableDuration } }
    var roundedTotal: TimeInterval { report.byProject.reduce(0) { $0 + $1.roundedDuration } }
    var entryCount: Int { report.byProject.reduce(0) { $0 + $1.entryCount } }

    // MARK: Monate

    /// Index des laufenden Monats, wenn das Jahr das aktuelle ist.
    var currentMonthIndex: Int? {
        guard report.interval.contains(now) else { return nil }
        return calendar.component(.month, from: now) - 1
    }

    /// Monat beginnt nach `now` (im aktuellen Jahr die restlichen Monate, in künftigen Jahren alle).
    func isFuture(_ index: Int) -> Bool {
        guard report.months.indices.contains(index) else { return false }
        return report.months[index].month > now
    }

    /// Ungerundete Zeit eines Projekts je Monat (12 Werte).
    func months(for projectId: UUID) -> [TimeInterval] {
        projectMonths[projectId] ?? Array(repeating: 0, count: 12)
    }

    // MARK: Vorjahr

    /// Veränderung der Gesamtzeit gegenüber dem ganzen Vorjahr; `nil` ohne Vorjahreszeit.
    var totalDelta: Double? {
        guard report.previousYearTotal > 0 else { return nil }
        return report.total / report.previousYearTotal - 1
    }

    /// Veränderung des Umsatzes gegenüber dem ganzen Vorjahr; `nil` ohne Vorjahresumsatz.
    var amountDelta: Double? {
        let previous = NSDecimalNumber(decimal: report.previousYearAmount).doubleValue
        guard previous > 0 else { return nil }
        return NSDecimalNumber(decimal: report.amount).doubleValue / previous - 1
    }

    // MARK: Kunden

    /// Gerundete abrechenbare Zeit je Kunde. `ClientRow` führt nur die ungerundete; der Betrag
    /// rechnet aber mit der gerundeten, darum hier aus den Projektzeilen nachgerechnet
    /// (gleiche Zusammenfassung wie in TaktCore: getrimmt, ohne Groß-/Kleinschreibung und Akzente).
    func roundedBillable(for client: ClientRow) -> TimeInterval {
        let key = Self.clientKey(client.client)
        return report.byProject
            .filter { Self.clientKey($0.project.client) == key }
            .reduce(0) { $0 + $1.roundedBillableDuration }
    }

    static func clientKey(_ name: String?) -> String {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return "" }
        return trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                               locale: Locale(identifier: "de_DE"))
    }

    // MARK: Rechnen

    /// Verteilt die Einträge auf Projekt × Monat (zugeschnitten auf die Monatsgrenzen).
    static func projectMonths(entries: [TimeEntry], months: [Date], yearEnd: Date, now: Date) -> [UUID: [TimeInterval]] {
        guard months.count == 12 else { return [:] }
        let bounds = months + [yearEnd]
        var result: [UUID: [TimeInterval]] = [:]
        for entry in entries {
            let end = entry.endedAt ?? max(now, entry.startedAt)
            guard end > entry.startedAt, entry.startedAt < yearEnd, end > bounds[0] else { continue }
            var values = result[entry.projectId] ?? Array(repeating: 0, count: 12)
            for index in 0..<12 {
                let start = max(entry.startedAt, bounds[index])
                let stop = min(end, bounds[index + 1])
                if stop > start { values[index] += stop.timeIntervalSince(start) }
            }
            result[entry.projectId] = values
        }
        return result
    }
}

// MARK: - Jahr als Zeitraum

/// Hilfen für das Jahr als Zeitraum in der Oberfläche (`ReportPeriod` kennt kein Jahr).
enum ReportsYear {
    /// 1. Januar bis 1. Januar des Folgejahres (exklusiv) – wie `YearReport.interval`.
    static func interval(_ year: Int, calendar: Calendar) -> DateInterval {
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? .distantPast
        let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? start
        return DateInterval(start: start, end: max(start, end))
    }

    /// Jahr, das zu einem bisherigen Zeitraum passt: das heutige, wenn er heute enthält, sonst das
    /// seines Anfangs.
    static func year(for interval: DateInterval, now: Date, calendar: Calendar) -> Int {
        calendar.component(.year, from: interval.contains(now) ? now : interval.start)
    }
}

// MARK: - Formate

extension ReportsFormat {
    static let monthsLong = ["Januar", "Februar", "März", "April", "Mai", "Juni",
                             "Juli", "August", "September", "Oktober", "November", "Dezember"]
    static let monthInitials = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]

    /// Veränderung mit Vorzeichen: „+12 %“, „−8 %“, „±0 %“.
    static func delta(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "–" }
        let percent = Int((fraction * 100).rounded())
        if percent > 0 { return "+\(percent) %" }
        if percent < 0 { return "\u{2212}\(-percent) %" }
        return "±0 %"
    }

    /// Ganzzahl mit Tausenderpunkt, „12.400“.
    static func grouped(_ value: Double) -> String {
        let number = Int(value.rounded())
        let digits = String(abs(number))
        var groups: [String] = []
        var rest = Substring(digits)
        while rest.count > 3 {
            groups.insert(String(rest.suffix(3)), at: 0)
            rest = rest.dropLast(3)
        }
        groups.insert(String(rest), at: 0)
        return (number < 0 ? "-" : "") + groups.joined(separator: ".")
    }

    /// Währungszeichen zum ISO-Code („EUR“ → „€“, „CHF“ → „CHF“).
    static func currencySymbol(_ code: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        let symbol = formatter.currencySymbol ?? code
        return symbol.isEmpty ? code : symbol
    }

    /// „1 aktiver Tag“, „212 aktive Tage“.
    static func activeDays(_ count: Int) -> String {
        count == 1 ? "1 aktiver Tag" : "\(count) aktive Tage"
    }
}
