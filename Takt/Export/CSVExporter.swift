import AppKit
import Foundation
import TaktCore
import UniformTypeIdentifiers

/// Speichert Berichte als CSV-Datei über einen Sichern-Dialog. Der Inhalt kommt aus
/// `CSVExport` (deutsches Excel: `;`, Dezimalkomma, CRLF, BOM bereits im Text).
enum CSVExporter {
    enum Kind {
        case entries, summary
        /// Jahresübersicht: Monatszeilen und Kundentabelle (Reiter „Jahr“).
        case year

        var fileLabel: String {
            switch self {
            case .entries: "Einträge"
            case .summary: "Zusammenfassung"
            case .year: "Jahr"
            }
        }
    }

    /// Dateiname für den Reiter „Jahr“: „Takt_Jahr_2026.csv“, „Takt_Einträge_2026.csv“.
    static func fileName(_ kind: Kind, year: Int) -> String {
        "Takt_\(kind.fileLabel)_\(String(year)).csv"
    }

    /// Dateiname wie „Takt_Einträge_2026-10_KW43.csv“, „Takt_Zusammenfassung_2026-10.csv“,
    /// „Takt_Einträge_2026-10-20.csv“ oder „Takt_Einträge_2026-10-01_bis_2026-10-15.csv“.
    static func fileName(_ kind: Kind, period: ReportPeriod, calendar: Calendar = .current) -> String {
        "Takt_\(kind.fileLabel)_\(periodStamp(period, calendar: calendar)).csv"
    }

    static func periodStamp(_ period: ReportPeriod, calendar: Calendar) -> String {
        let interval = period.interval(calendar: calendar)
        switch period {
        case .day(let date):
            return day(date, calendar: calendar)
        case .week:
            // KW nach ISO 8601; Jahr und Monat vom Donnerstag der Woche (bestimmt das KW-Jahr).
            var iso = calendar
            iso.firstWeekday = 2
            iso.minimumDaysInFirstWeek = 4
            let thursday = iso.date(byAdding: .day, value: 3, to: interval.start) ?? interval.start
            let c = iso.dateComponents([.year, .month], from: thursday)
            let week = iso.component(.weekOfYear, from: thursday)
            return String(format: "%04d-%02d_KW%02d", c.year ?? 0, c.month ?? 0, week)
        case .month(let date):
            let c = calendar.dateComponents([.year, .month], from: date)
            return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
        case .custom:
            let last = interval.end > interval.start ? interval.end.addingTimeInterval(-1) : interval.start
            let first = day(interval.start, calendar: calendar)
            let lastDay = day(last, calendar: calendar)
            return first == lastDay ? first : "\(first)_bis_\(lastDay)"
        }
    }

    private static func day(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: Jahr

    /// Jahresübersicht im selben Format wie `CSVExport` (`;`, Dezimalkomma, CRLF, BOM):
    /// Kopf (Jahr, Währung, Rundung), Monatstabelle mit Summenzeile, Leerzeile, Kundentabelle mit
    /// Summenzeile. „Abrechenbar“ ist je Eintrag gerundet (Grundlage der Beträge); die Summe der
    /// Monatsbeträge kann um Cent vom Jahresbetrag abweichen (Einträge über Monatsgrenzen).
    static func yearCSV(_ data: YearReportsData) -> String {
        let report = data.report
        let money: (Decimal) -> String = { data.hasAnyRate ? Money.germanString($0) : "" }
        var lines: [[String]] = [
            ["Jahr", String(report.year)],
            ["Währung", data.currencyCode],
            ["Rundung", ReportsFormat.roundingHint(data.rounding)],
            [],
            ["Monat", "Dauer (h:mm)", "Dauer (dezimal)", "Business (h:mm)", "Privat (h:mm)",
             "Abrechenbar (dezimal)", "Betrag", "Aktive Tage"],
        ]
        for (index, month) in report.months.enumerated() {
            lines.append([
                ReportsFormat.monthsLong[index],
                DurationFormat.hourMinute(month.total),
                decimalHours(month.total),
                DurationFormat.hourMinute(month.business),
                DurationFormat.hourMinute(month.personal),
                decimalHours(month.roundedBillable),
                money(month.amount),
                String(month.activeDays),
            ])
        }
        lines.append([
            "Summe",
            DurationFormat.hourMinute(report.total),
            decimalHours(report.total),
            DurationFormat.hourMinute(report.business),
            DurationFormat.hourMinute(report.personal),
            decimalHours(data.roundedBillable),
            money(report.amount),
            String(report.activeDays),
        ])
        lines.append([])
        lines.append(["Kunde", "Projekte", "Dauer (h:mm)", "Dauer (dezimal)", "Abrechenbar (dezimal)", "Betrag"])
        for client in report.byClient {
            lines.append([
                client.client ?? "ohne Kunde",
                String(client.projectCount),
                DurationFormat.hourMinute(client.duration),
                decimalHours(client.duration),
                decimalHours(data.roundedBillable(for: client)),
                money(client.amount),
            ])
        }
        lines.append([
            "Summe",
            String(report.byProject.count),
            DurationFormat.hourMinute(report.total),
            decimalHours(report.total),
            decimalHours(data.roundedBillable),
            money(report.amount),
        ])
        return "\u{FEFF}" + lines.map(csvLine).joined(separator: "\r\n") + "\r\n"
    }

    /// Felder mit `;`, `"` oder Zeilenumbruch in Anführungszeichen (`"` verdoppelt) – wie `CSVExport`.
    private static func csvLine(_ fields: [String]) -> String {
        fields.map { field in
            guard field.contains(where: { $0 == ";" || $0 == "\"" || $0.isNewline }) else { return field }
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        .joined(separator: ";")
    }

    /// Stunden mit zwei Nachkommastellen und Komma, z. B. 5400 s → „1,50“.
    private static func decimalHours(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0,00" }
        let millis = Decimal(Int64((seconds * 1000).rounded()))
        return Money.germanString(millis / 3_600_000)
    }

    /// Fragt nach dem Speicherort und schreibt `content` als UTF-8.
    /// - Returns: Ziel-URL; `nil`, wenn der Dialog abgebrochen wurde.
    /// - Throws: Schreibfehler.
    @MainActor
    static func save(_ content: String, suggestedName: String) async throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "Bericht exportieren"
        panel.prompt = "Sichern"
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = panel.runModal()
        }
        guard response == .OK, let url = panel.url else { return nil }
        // Der BOM steht schon am Anfang von `content` und wird so zu EF BB BF.
        try Data(content.utf8).write(to: url, options: .atomic)
        return url
    }
}
