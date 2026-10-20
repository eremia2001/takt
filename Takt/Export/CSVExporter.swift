import AppKit
import Foundation
import TaktCore
import UniformTypeIdentifiers

/// Speichert Berichte als CSV-Datei über einen Sichern-Dialog. Der Inhalt kommt aus
/// `CSVExport` (deutsches Excel: `;`, Dezimalkomma, CRLF, BOM bereits im Text).
enum CSVExporter {
    enum Kind {
        case entries, summary

        var fileLabel: String {
            switch self {
            case .entries: "Einträge"
            case .summary: "Zusammenfassung"
            }
        }
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
