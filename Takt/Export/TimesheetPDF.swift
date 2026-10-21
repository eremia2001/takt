import AppKit
import SwiftUI
import TaktCore
import UniformTypeIdentifiers

// Tätigkeitsnachweis (Timesheet) als PDF für Kunden. Die Zahlen kommen aus `Timesheet` (TaktCore),
// hier liegen nur Seitenaufteilung und Darstellung.
//
// Erzeugung: Jede Seite ist eine SwiftUI-View (A4 hochkant, 595 × 842 pt), die `ImageRenderer`
// direkt in einen PDF-`CGContext` zeichnet – Text bleibt Vektor (durchsuchbar, scharf).
// Seitenumbruch über ein Höhenbudget: Zeilen haben feste Höhen (ein- bis dreizeilig, vorab mit
// SwiftUI in derselben Schrift und Breite gemessen), daraus ergeben sich rund 34 Einträge je Seite.
// Ruhige Typografie: Systemschrift, Grautöne, dünne Linien, keine Farben.

/// Kopfangaben und Darstellungsoptionen des Nachweises (beeinflussen die Zahlen nicht).
struct TimesheetDocument {
    /// Aussteller (Name, Firma, Anschrift) – Freitext, mehrzeilig.
    var issuer: String
    /// Kundenname im Kopf; leer = „–“.
    var clientName: String
    /// Projektname, wenn der Nachweis nur ein Projekt umfasst.
    var projectName: String?
    var showNotes = true
    var showTags = true
    var daySubtotals = false
    var currencyCode = "EUR"
    var createdAt = Date.now
    var calendar = Calendar.current
}

enum TimesheetPDF {
    static let pageSize = CGSize(width: 595, height: 842)

    // MARK: Erzeugen

    /// Rendert das Timesheet als PDF-Daten (mindestens eine Seite, auch ohne Einträge).
    @MainActor
    static func render(_ sheet: Timesheet, document: TimesheetDocument) -> Data {
        let layout = TimesheetLayout(sheet: sheet, document: document)
        let pages = layout.paginate()

        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let info: [CFString: Any] = [
            kCGPDFContextTitle: "Tätigkeitsnachweis \(layout.periodTitle)",
            kCGPDFContextCreator: "Takt",
            kCGPDFContextAuthor: document.issuer.split(separator: "\n").first.map(String.init) ?? "",
        ]
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary)
        else { return Data() }

        for page in pages {
            let view = TimesheetPageView(page: page, pageCount: pages.count, layout: layout)
                .environment(\.colorScheme, .light)
                .environment(\.locale, Locale(identifier: "de_DE"))
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render(rasterizationScale: 1) { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return data as Data
    }

    // MARK: Dateiname

    /// „Timesheet_Müller_GmbH_2026-10.pdf“; ganzer Monat → „2026-10“, ganzes Jahr → „2026“,
    /// sonst Tage wie beim CSV-Export („2026-10-01_bis_2026-10-15“).
    static func fileName(label: String, interval: DateInterval, calendar: Calendar = .current) -> String {
        "Timesheet_\(sanitized(label))_\(stamp(interval, calendar: calendar)).pdf"
    }

    static func stamp(_ interval: DateInterval, calendar: Calendar) -> String {
        if let month = calendar.dateInterval(of: .month, for: interval.start), month == interval {
            return CSVExporter.periodStamp(.month(interval.start), calendar: calendar)
        }
        if let year = calendar.dateInterval(of: .year, for: interval.start), year == interval {
            return String(calendar.component(.year, from: interval.start))
        }
        return CSVExporter.periodStamp(.custom(interval), calendar: calendar)
    }

    /// Ohne Zeichen, die Finder/Dateisysteme stören; Leerraum wird zu „_“.
    static func sanitized(_ label: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?*\"<>|")
        let cleaned = label.unicodeScalars.filter { !forbidden.contains($0) }
        let words = String(String.UnicodeScalarView(cleaned))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return words.isEmpty ? "Alle" : words.joined(separator: "_")
    }

    // MARK: Sichern

    /// Fragt nach dem Speicherort und schreibt das PDF.
    /// - Returns: Ziel-URL; `nil`, wenn der Dialog abgebrochen wurde.
    @MainActor
    static func save(_ data: Data, suggestedName: String) async throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "Timesheet sichern"
        panel.prompt = "Sichern"
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = panel.runModal()
        }
        guard response == .OK, let url = panel.url else { return nil }
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: Formate

    /// „95,00 €“, „4.061,25 €“ – mit Tausenderpunkt, Währungszeichen zum ISO-Code.
    static func money(_ value: Decimal, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: Money.round(value, scale: 2)))
            ?? "\(Money.germanString(value)) \(currencyCode)"
    }

    /// Stunden dezimal mit zwei Stellen: 5400 s → „1,50“.
    static func decimalHours(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0,00" }
        let millis = Decimal(Int64((seconds * 1000).rounded()))
        return Money.germanString(millis / 3_600_000)
    }

    static func hours(_ seconds: TimeInterval) -> String { DurationFormat.hourMinute(seconds) }

    /// „Mo 05.10.“
    static func shortDay(_ date: Date, calendar: Calendar) -> String {
        let weekdays = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
        let c = calendar.dateComponents([.weekday, .day, .month], from: date)
        return String(format: "%@ %02d.%02d.", weekdays[(c.weekday ?? 1) - 1], c.day ?? 0, c.month ?? 0)
    }

    /// „09:05“
    static func clock(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// „21.10.2026“
    static func longDate(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.day, .month, .year], from: date)
        return String(format: "%02d.%02d.%04d", c.day ?? 0, c.month ?? 0, c.year ?? 0)
    }

    /// Hinweis zur Rundung unter der Summe.
    static func roundingNote(_ rounding: Rounding) -> String {
        switch rounding {
        case .none: "Alle Zeiten ungerundet."
        case .minutes6: "Dezimalstunden je Eintrag auf 6 Minuten (0,1 h) aufgerundet; Zeiten in h:mm ungerundet."
        case .minutes15: "Dezimalstunden je Eintrag auf 15 Minuten aufgerundet; Zeiten in h:mm ungerundet."
        case .minutes30: "Dezimalstunden je Eintrag auf 30 Minuten aufgerundet; Zeiten in h:mm ungerundet."
        }
    }
}

// MARK: - Seitenaufteilung

/// Maße, Spalten und Zeilen des Nachweises; teilt die Zeilen auf Seiten auf.
struct TimesheetLayout {
    let sheet: Timesheet
    let document: TimesheetDocument
    /// Zeilenzahl je Eintrag (1…3), vorab gemessen.
    private(set) var lineCounts: [UUID: Int] = [:]
    /// Zeilenzahl der Kopfangaben „Kunde“ und „Projekt(e)“ (1…2).
    private(set) var clientLines = 1
    private(set) var projectLines = 1
    /// Zeilenzahl je Ausstellerzeile (1…2).
    private(set) var issuerLineCounts: [Int] = []

    @MainActor
    init(sheet: Timesheet, document: TimesheetDocument) {
        self.sheet = sheet
        self.document = document
        let measure = TextMeasure()
        for line in sheet.lines {
            var count = 1
            if showsActivity {
                count = max(count, measure.lines(activityPlain(line), width: activityWidth, size: Self.bodyFontSize))
            }
            if showsProject {
                count = max(count, measure.lines(line.project.name, width: Self.projectWidth, size: Self.bodyFontSize))
            }
            lineCounts[line.id] = min(Self.maxLines, count)
        }
        clientLines = min(2, measure.lines(clientText, width: Self.metaValueWidth, size: Self.metaFontSize, weight: .medium))
        projectLines = min(2, measure.lines(projectText, width: Self.metaValueWidth, size: Self.metaFontSize, weight: .medium))
        issuerLineCounts = issuerLines.enumerated().map { index, text in
            min(2, measure.lines(text, width: Self.issuerWidth, size: Self.metaFontSize, weight: index == 0 ? .medium : .regular))
        }
    }

    // Seitenränder und feste Höhen (pt).
    static let marginX: CGFloat = 46
    static let marginTop: CGFloat = 46
    static let marginBottom: CGFloat = 30
    static let footerHeight: CGFloat = 18
    static let footerGap: CGFloat = 14
    static let continuationHeaderHeight: CGFloat = 34
    static let tableHeaderHeight: CGFloat = 20
    /// Höhe einer einzeiligen Zeile; jede weitere Textzeile kommt mit `extraLineHeight` dazu.
    static let lineHeight: CGFloat = 18
    static let extraLineHeight: CGFloat = 11
    static let maxLines = 3
    static let daySumHeight: CGFloat = 20
    static let totalHeight: CGFloat = 24
    static let summaryLineHeight: CGFloat = 15
    static let noteLineHeight: CGFloat = 11
    static let columnGap: CGFloat = 9

    static let bodyFontSize: CGFloat = 9
    static var contentWidth: CGFloat { TimesheetPDF.pageSize.width - 2 * marginX }

    // Spaltenbreiten; „Tätigkeit“ nimmt den Rest.
    static let dateWidth: CGFloat = 52
    static let timeWidth: CGFloat = 60
    static let projectWidth: CGFloat = 86
    static let durationWidth: CGFloat = 34
    static let decimalWidth: CGFloat = 48

    var showsProject: Bool { sheet.hasSeveralProjects }
    var showsActivity: Bool { document.showNotes || document.showTags || sheet.hasNonBillable }

    var activityWidth: CGFloat {
        var fixed = Self.dateWidth + Self.timeWidth + Self.durationWidth + Self.decimalWidth
        var gaps = 3
        if showsProject { fixed += Self.projectWidth; gaps += 1 }
        if showsActivity { gaps += 1 }
        return max(60, Self.contentWidth - fixed - CGFloat(gaps) * Self.columnGap)
    }

    var periodTitle: String { sheet.periodTitle(calendar: document.calendar) }

    // MARK: Kopf Seite 1

    /// Zeilen des Ausstellers (höchstens fünf, leere entfernt).
    var issuerLines: [String] {
        let lines = document.issuer
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Array(lines.prefix(5))
    }

    // Kopfangaben: links Zeitraum/Kunde/Projekt (Beschriftung + Wert), rechts der Aussteller.
    static let metaFontSize: CGFloat = 9.5
    static let metaLineHeight: CGFloat = 13
    static let metaRowGap: CGFloat = 4
    static let metaLabelWidth: CGFloat = 62
    static let issuerWidth: CGFloat = 180
    static var metaValueWidth: CGFloat { contentWidth - issuerWidth - 30 - metaLabelWidth }

    var clientText: String { document.clientName.isEmpty ? "–" : document.clientName }

    /// Projekt des Nachweises bzw. alle Projekte in der Reihenfolge ihres ersten Eintrags.
    var projectText: String {
        if let name = document.projectName { return name }
        var seen: Set<UUID> = []
        let names = sheet.lines.compactMap { seen.insert($0.project.id).inserted ? $0.project.name : nil }
        return names.isEmpty ? "–" : names.joined(separator: ", ")
    }

    var metaBlockHeight: CGFloat {
        let left = CGFloat(1 + clientLines + projectLines) * Self.metaLineHeight + 2 * Self.metaRowGap
        let right = 12 + CGFloat(max(1, issuerLineCounts.reduce(0, +))) * Self.metaLineHeight
        return max(left, right)
    }

    /// Titel (Tätigkeitsnachweis + Zeile darunter), Linie, Angaben, Abstand zur Tabelle.
    var firstHeaderHeight: CGFloat {
        30 + 16 + 18 + metaBlockHeight + 24
    }

    // MARK: Zeilen

    enum Row: Hashable {
        /// Ein Eintrag; `showsDate` beim ersten Eintrag eines Tages (und oben auf jeder Seite).
        case line(TimesheetLine, showsDate: Bool, lineCount: Int, separatorAbove: Bool)
        case daySum(TimesheetDay)
        case total

        var height: CGFloat {
            switch self {
            case .line(_, _, let count, _):
                TimesheetLayout.lineHeight + CGFloat(max(0, count - 1)) * TimesheetLayout.extraLineHeight
            case .daySum: TimesheetLayout.daySumHeight
            case .total: TimesheetLayout.totalHeight
            }
        }
    }

    struct Page: Identifiable {
        let id: Int
        var rows: [Row]
        var isLast = false
    }

    /// Text der Spalte „Tätigkeit“ (für Messung und Darstellung).
    func activityParts(_ line: TimesheetLine) -> (note: String?, tag: String?, nonBillable: Bool) {
        (document.showNotes ? line.note : nil,
         document.showTags ? line.tag : nil,
         !line.isBillable)
    }

    func activityPlain(_ line: TimesheetLine) -> String {
        let parts = activityParts(line)
        var pieces: [String] = []
        if let note = parts.note { pieces.append(note) }
        if let tag = parts.tag { pieces.append(tag) }
        if parts.nonBillable { pieces.append("nicht abrechenbar") }
        return pieces.joined(separator: " · ")
    }

    /// Zeilenzahl eines Eintrags (1…3), siehe `init`.
    func lineCount(_ line: TimesheetLine) -> Int { lineCounts[line.id] ?? 1 }

    /// Alle Zeilen in Reihenfolge (ohne Seitenbezug).
    func rows() -> [Row] {
        var rows: [Row] = []
        for (dayIndex, day) in sheet.days.enumerated() {
            for (index, line) in day.lines.enumerated() {
                rows.append(.line(line, showsDate: index == 0, lineCount: lineCount(line),
                                  separatorAbove: index == 0 && dayIndex > 0 && !document.daySubtotals))
            }
            if document.daySubtotals { rows.append(.daySum(day)) }
        }
        rows.append(.total)
        return rows
    }

    // MARK: Zusammenfassung

    struct SummaryLine: Hashable {
        var label: String
        var value: String
        var emphasized = false
    }

    var summaryLines: [SummaryLine] {
        let money = { TimesheetPDF.money($0, currencyCode: document.currencyCode) }
        let rounding = sheet.options.rounding
        var lines: [SummaryLine] = []
        if rounding == .none {
            lines.append(SummaryLine(label: "Stunden gesamt",
                                     value: "\(TimesheetPDF.hours(sheet.totalDuration)) h · \(TimesheetPDF.decimalHours(sheet.totalDuration)) h"))
        } else {
            lines.append(SummaryLine(label: "Erfasste Zeit", value: "\(TimesheetPDF.hours(sheet.totalDuration)) h"))
            lines.append(SummaryLine(label: "Abgerechnete Zeit",
                                     value: "\(TimesheetPDF.hours(sheet.totalBilledDuration)) h · \(TimesheetPDF.decimalHours(sheet.totalBilledDuration)) h"))
        }
        if sheet.hasNonBillable {
            lines.append(SummaryLine(label: "davon abrechenbar",
                                     value: "\(TimesheetPDF.hours(sheet.billableBilledDuration)) h · \(TimesheetPDF.decimalHours(sheet.billableBilledDuration)) h"))
        }
        if sheet.rateGroups.count == 1, let rate = sheet.hourlyRate {
            lines.append(SummaryLine(label: "Stundensatz", value: "\(money(rate)) / h"))
        } else if sheet.rateGroups.count > 1 {
            for group in sheet.rateGroups {
                lines.append(SummaryLine(label: "\(TimesheetPDF.decimalHours(group.billedDuration)) h × \(money(group.rate))",
                                         value: money(group.amount)))
            }
        }
        if let amount = sheet.amount {
            lines.append(SummaryLine(label: "Betrag", value: money(amount), emphasized: true))
        }
        return lines
    }

    var summaryNotes: [String] {
        var notes = [TimesheetPDF.roundingNote(sheet.options.rounding)]
        if sheet.amount != nil, sheet.hasNonBillable {
            notes.append("Nicht abrechenbare Einträge sind gekennzeichnet und im Betrag nicht enthalten.")
        }
        if sheet.amount != nil, sheet.billableWithoutRate > 0 {
            notes.append("\(TimesheetPDF.hours(sheet.billableWithoutRate)) h ohne Stundensatz sind im Betrag nicht enthalten.")
        }
        return notes
    }

    static let summaryGap: CGFloat = 18

    var summaryHeight: CGFloat {
        let emphasized = summaryLines.contains(where: \.emphasized) ? 8 : 0
        return Self.summaryGap + CGFloat(summaryLines.count) * Self.summaryLineHeight + CGFloat(emphasized)
            + 12 + CGFloat(summaryNotes.count) * Self.noteLineHeight
    }

    // MARK: Aufteilen

    /// Verfügbare Höhe für Tabellenzeilen auf einer Seite.
    func bodyHeight(first: Bool) -> CGFloat {
        TimesheetPDF.pageSize.height - Self.marginTop - Self.marginBottom - Self.footerHeight - Self.footerGap
            - (first ? firstHeaderHeight : Self.continuationHeaderHeight) - Self.tableHeaderHeight
    }

    /// Verteilt die Zeilen auf Seiten. Die Summenzeile steht mit der Zusammenfassung auf der letzten
    /// Seite; eine Tagessumme wird nicht von ihrem letzten Eintrag getrennt; oben auf einer neuen
    /// Seite steht das Datum erneut.
    func paginate() -> [Page] {
        let all = rows()
        var pages: [Page] = []
        var current: [Row] = []
        var used: CGFloat = 0
        var budget = bodyHeight(first: true)

        func newPage() {
            pages.append(Page(id: pages.count, rows: current))
            current = []
            used = 0
            budget = bodyHeight(first: false)
        }

        var index = 0
        while index < all.count {
            var row = all[index]
            // Am Ende muss die Zusammenfassung mit auf die Seite.
            let extra: CGFloat = (row == .total) ? summaryHeight : 0
            if used + row.height + extra > budget, !current.isEmpty {
                // Tagessumme nicht allein oben auf die neue Seite: letzten Eintrag mitnehmen.
                var carried: Row?
                if case .daySum = row, case .line = current.last, current.count > 1 {
                    carried = current.removeLast()
                }
                newPage()
                if let carried {
                    current.append(withDate(carried))
                    used += carried.height
                }
                if case .line = row, carried == nil { row = withDate(row) }
            }
            current.append(row)
            used += row.height
            index += 1
        }
        if !current.isEmpty || pages.isEmpty { newPage() }
        pages[pages.count - 1].isLast = true
        return pages
    }

    /// Dieselbe Zeile mit Datum und ohne Trennlinie (oben auf einer Seite).
    private func withDate(_ row: Row) -> Row {
        guard case .line(let line, _, let count, _) = row else { return row }
        return .line(line, showsDate: true, lineCount: count, separatorAbove: false)
    }
}

// MARK: - Seite

/// Eine A4-Seite des Nachweises.
struct TimesheetPageView: View {
    let page: TimesheetLayout.Page
    let pageCount: Int
    let layout: TimesheetLayout

    private typealias L = TimesheetLayout
    private var document: TimesheetDocument { layout.document }
    private var sheet: Timesheet { layout.sheet }
    private var calendar: Calendar { document.calendar }

    // Grautöne statt Farben.
    private let ink = Color(white: 0.12)
    private let secondary = Color(white: 0.40)
    private let tertiary = Color(white: 0.58)
    private let rule = Color(white: 0.84)
    private let strongRule = Color(white: 0.30)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if page.id == 0 {
                firstHeader.frame(height: layout.firstHeaderHeight, alignment: .top)
            } else {
                continuationHeader.frame(height: L.continuationHeaderHeight, alignment: .top)
            }
            tableHeader.frame(height: L.tableHeaderHeight)
            ForEach(Array(page.rows.enumerated()), id: \.offset) { _, row in
                rowView(row).frame(height: row.height)
            }
            if page.isLast {
                summary.frame(height: layout.summaryHeight, alignment: .top)
            }
            Spacer(minLength: 0)
            footer
                .frame(height: L.footerHeight)
                .padding(.top, L.footerGap)
        }
        .padding(.horizontal, L.marginX)
        .padding(.top, L.marginTop)
        .padding(.bottom, L.marginBottom)
        .frame(width: TimesheetPDF.pageSize.width, height: TimesheetPDF.pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(ink)
    }

    // MARK: Kopf

    private var firstHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tätigkeitsnachweis")
                    .font(.system(size: 22, weight: .semibold))
                    .kerning(-0.2)
                Spacer()
                Text("Timesheet")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(tertiary)
            }
            .frame(height: 30, alignment: .bottom)
            Text(layout.periodTitle)
                .font(.system(size: 11))
                .foregroundStyle(secondary)
                .frame(height: 16, alignment: .top)
            Rectangle().fill(strongRule).frame(height: 0.75)
                .padding(.top, 9)
                .padding(.bottom, 9)
            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: L.metaRowGap) {
                    metaRow("Zeitraum", GermanRange.text(sheet.interval, calendar: calendar), lines: 1)
                    metaRow("Kunde", layout.clientText, lines: layout.clientLines)
                    metaRow(sheet.hasSeveralProjects ? "Projekte" : "Projekt", layout.projectText, lines: layout.projectLines)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !layout.issuerLines.isEmpty {
                    issuerBlock
                }
            }
        }
    }

    /// Aussteller rechts im Kopf (ohne Angabe entfällt der Block).
    private var issuerBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            caps("Aussteller")
                .frame(height: 12, alignment: .top)
            ForEach(Array(layout.issuerLines.enumerated()), id: \.offset) { index, value in
                let lines = layout.issuerLineCounts.indices.contains(index) ? layout.issuerLineCounts[index] : 1
                Text(value)
                    .font(.system(size: L.metaFontSize, weight: index == 0 ? .medium : .regular))
                    .foregroundStyle(index == 0 ? ink : secondary)
                    .lineLimit(lines)
                    .truncationMode(.tail)
                    .frame(height: CGFloat(lines) * L.metaLineHeight, alignment: .topLeading)
            }
        }
        .frame(width: L.issuerWidth, alignment: .leading)
    }

    /// „KUNDE   Müller GmbH“ – Beschriftung auf der Grundlinie des Werts.
    private func metaRow(_ label: String, _ value: String, lines: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            caps(label)
                .frame(width: L.metaLabelWidth, alignment: .leading)
            Text(value)
                .font(.system(size: L.metaFontSize, weight: .medium))
                .lineLimit(lines)
                .truncationMode(.tail)
                .lineSpacing(1)
                .frame(width: L.metaValueWidth, alignment: .leading)
        }
        .frame(height: CGFloat(lines) * L.metaLineHeight, alignment: .topLeading)
    }

    private var continuationHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Tätigkeitsnachweis")
                    .font(.system(size: 9.5, weight: .semibold))
                Text([document.clientName.isEmpty ? nil : document.clientName, layout.periodTitle]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 9.5))
                    .foregroundStyle(secondary)
                    .lineLimit(1)
                Spacer()
            }
            .frame(height: 14)
            Rectangle().fill(strongRule).frame(height: 0.75)
                .padding(.top, 6)
        }
    }

    private func caps(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 7, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(tertiary)
    }

    // MARK: Tabelle

    private var tableHeader: some View {
        HStack(spacing: L.columnGap) {
            caps("Datum").frame(width: L.dateWidth, alignment: .leading)
            caps("Von–Bis").frame(width: L.timeWidth, alignment: .leading)
            if layout.showsProject {
                caps("Projekt").frame(width: L.projectWidth, alignment: .leading)
            }
            if layout.showsActivity {
                caps("Tätigkeit").frame(width: layout.activityWidth, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
            caps("Dauer").frame(width: L.durationWidth, alignment: .trailing)
            caps(sheet.options.rounding == .none ? "Stunden" : "Std. ger.")
                .frame(width: L.decimalWidth, alignment: .trailing)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 5)
        .overlay(alignment: .bottom) {
            Rectangle().fill(rule).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func rowView(_ row: TimesheetLayout.Row) -> some View {
        switch row {
        case .line(let line, let showsDate, let count, let separatorAbove):
            lineRow(line, showsDate: showsDate, lineCount: count)
                .overlay(alignment: .top) {
                    if separatorAbove { Rectangle().fill(rule.opacity(0.7)).frame(height: 0.5) }
                }
        case .daySum(let day):
            daySumRow(day)
        case .total:
            totalRow
        }
    }

    private func lineRow(_ line: TimesheetLine, showsDate: Bool, lineCount: Int) -> some View {
        // Oben ausgerichtet (gleiche Schrift in allen Spalten): Ein leeres Datum hätte keine
        // Grundlinie und verschöbe die Zeile.
        HStack(alignment: .top, spacing: L.columnGap) {
            Text(showsDate ? TimesheetPDF.shortDay(line.start, calendar: calendar) : "")
                .frame(width: L.dateWidth, alignment: .leading)
            Text("\(TimesheetPDF.clock(line.start, calendar: calendar))–\(TimesheetPDF.clock(line.end, calendar: calendar))")
                .foregroundStyle(secondary)
                .frame(width: L.timeWidth, alignment: .leading)
            if layout.showsProject {
                Text(line.project.name)
                    .foregroundStyle(secondary)
                    .lineLimit(lineCount)
                    .frame(width: L.projectWidth, alignment: .leading)
            }
            if layout.showsActivity {
                Text(activity(line))
                    .lineLimit(lineCount)
                    .truncationMode(.tail)
                    .frame(width: layout.activityWidth, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
            Text(TimesheetPDF.hours(line.duration))
                .frame(width: L.durationWidth, alignment: .trailing)
            Text(TimesheetPDF.decimalHours(line.billedDuration))
                .foregroundStyle(line.isBillable ? ink : tertiary)
                .frame(width: L.decimalWidth, alignment: .trailing)
        }
        .font(.system(size: L.bodyFontSize))
        .monospacedDigit()
        .padding(.top, 4)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Notiz in Schwarz, Tag und „nicht abrechenbar“ in Grau.
    private func activity(_ line: TimesheetLine) -> AttributedString {
        let parts = layout.activityParts(line)
        var result = AttributedString()
        func append(_ text: String, _ color: Color) {
            if !result.characters.isEmpty {
                var dot = AttributedString(" · ")
                dot.foregroundColor = tertiary
                result += dot
            }
            var piece = AttributedString(text)
            piece.foregroundColor = color
            result += piece
        }
        if let note = parts.note { append(note, ink) }
        if let tag = parts.tag { append(tag, secondary) }
        if parts.nonBillable { append("nicht abrechenbar", tertiary) }
        return result
    }

    private func daySumRow(_ day: TimesheetDay) -> some View {
        HStack(spacing: L.columnGap) {
            Spacer(minLength: 0)
            Text("Summe \(TimesheetPDF.shortDay(day.day, calendar: calendar))")
                .foregroundStyle(tertiary)
            Text(TimesheetPDF.hours(day.duration))
                .fontWeight(.medium)
                .foregroundStyle(secondary)
                .frame(width: L.durationWidth, alignment: .trailing)
            Text(TimesheetPDF.decimalHours(day.billedDuration))
                .fontWeight(.medium)
                .foregroundStyle(secondary)
                .frame(width: L.decimalWidth, alignment: .trailing)
        }
        .font(.system(size: 8.5))
        .monospacedDigit()
        .padding(.top, 3)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            Rectangle().fill(rule.opacity(0.7)).frame(height: 0.5)
        }
    }

    private var totalRow: some View {
        HStack(spacing: L.columnGap) {
            Text("Summe")
                .fontWeight(.semibold)
            Text(sheet.lines.count == 1 ? "1 Eintrag" : "\(sheet.lines.count) Einträge")
                .foregroundStyle(tertiary)
            Spacer(minLength: 0)
            Text(TimesheetPDF.hours(sheet.totalDuration))
                .fontWeight(.semibold)
                .frame(width: L.durationWidth + 20, alignment: .trailing)
            Text(TimesheetPDF.decimalHours(sheet.totalBilledDuration))
                .fontWeight(.semibold)
                .frame(width: L.decimalWidth, alignment: .trailing)
        }
        .font(.system(size: 9.5))
        .monospacedDigit()
        .frame(maxHeight: .infinity)
        .overlay(alignment: .top) {
            Rectangle().fill(strongRule).frame(height: 0.75)
        }
    }

    // MARK: Zusammenfassung

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(layout.summaryLines.enumerated()), id: \.offset) { _, line in
                        if line.emphasized {
                            Rectangle().fill(rule).frame(height: 0.5)
                                .padding(.top, 3)
                                .padding(.bottom, 5)
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Text(line.label)
                                .font(.system(size: line.emphasized ? 10 : 9, weight: line.emphasized ? .semibold : .regular))
                                .foregroundStyle(line.emphasized ? ink : secondary)
                            Spacer(minLength: 16)
                            Text(line.value)
                                .font(.system(size: line.emphasized ? 10 : 9, weight: line.emphasized ? .semibold : .medium))
                        }
                        .monospacedDigit()
                        .frame(height: L.summaryLineHeight)
                    }
                }
                .frame(width: 250)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(layout.summaryNotes.enumerated()), id: \.offset) { _, note in
                    Text(note)
                        .font(.system(size: 7.5))
                        .foregroundStyle(tertiary)
                        .lineLimit(1)
                        .frame(height: L.noteLineHeight, alignment: .leading)
                }
            }
            .padding(.top, 12)
        }
        .padding(.top, TimesheetLayout.summaryGap)
    }

    // MARK: Fußzeile

    private var footer: some View {
        HStack {
            Text("Erstellt mit Takt am \(TimesheetPDF.longDate(document.createdAt, calendar: calendar))")
            Spacer()
            Text("Seite \(page.id + 1) von \(pageCount)")
                .monospacedDigit()
        }
        .font(.system(size: 7.5))
        .foregroundStyle(tertiary)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .overlay(alignment: .top) {
            Rectangle().fill(rule).frame(height: 0.5)
        }
    }
}

/// Zeitraum als Tagesspanne mit vollem Datum: „01.10.–31.10.2026“, „28.12.2025–03.01.2026“.
enum GermanRange {
    static func text(_ interval: DateInterval, calendar: Calendar) -> String {
        let last = interval.end > interval.start ? interval.end.addingTimeInterval(-1) : interval.start
        let a = calendar.dateComponents([.day, .month, .year], from: interval.start)
        let b = calendar.dateComponents([.day, .month, .year], from: last)
        if a.year == b.year, a.month == b.month, a.day == b.day {
            return TimesheetPDF.longDate(interval.start, calendar: calendar)
        }
        if a.year == b.year {
            return String(format: "%02d.%02d.–%02d.%02d.%04d", a.day ?? 0, a.month ?? 0, b.day ?? 0, b.month ?? 0, b.year ?? 0)
        }
        return "\(TimesheetPDF.longDate(interval.start, calendar: calendar))–\(TimesheetPDF.longDate(last, calendar: calendar))"
    }
}

/// Misst Textzeilen genau so, wie `ImageRenderer` sie ins PDF setzt (gleiche Schrift, Breite und
/// Umbruchregeln). Bildschirm-Messungen (AppKit, `NSHostingView`) fallen bei kleinen Größen einige
/// Prozent breiter aus und brächen zu früh um.
@MainActor
final class TextMeasure {
    private var singleLine: [String: CGFloat] = [:]

    func height(_ text: String, width: CGFloat, size: CGFloat, weight: Font.Weight = .regular) -> CGFloat {
        let view = Text(text)
            .font(.system(size: size, weight: weight))
            .monospacedDigit()
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.locale, Locale(identifier: "de_DE"))
        let renderer = ImageRenderer(content: view)
        var height: CGFloat = 0
        renderer.render { size, _ in height = size.height }
        return height
    }

    /// Anzahl der Zeilen, die `text` in `width` braucht (mindestens 1).
    func lines(_ text: String, width: CGFloat, size: CGFloat, weight: Font.Weight = .regular) -> Int {
        guard !text.isEmpty else { return 1 }
        let key = "\(size)-\(weight)"
        let one = singleLine[key] ?? height("Ag", width: 10_000, size: size, weight: weight)
        singleLine[key] = one
        guard one > 0 else { return 1 }
        return max(1, Int((height(text, width: width, size: size, weight: weight) / one).rounded()))
    }
}
