import Foundation

/// CSV für deutsches Excel/Numbers: Trennzeichen `;`, Dezimalkomma, UTF-8 mit BOM, Zeilenende CRLF.
/// Felder mit `;`, `"` oder Zeilenumbruch stehen in Anführungszeichen (`"` verdoppelt).
public enum CSVExport {
    static let separator = ";"
    static let lineEnding = "\r\n"
    static let byteOrderMark = "\u{FEFF}"

    /// Kopfzeile der Einzeleinträge.
    public static let entryHeader = [
        "Datum", "Start", "Ende", "Dauer (h:mm)", "Dauer (dezimal)", "Projekt", "Kunde",
        "Business/Privat", "Abrechenbar", "Stundensatz", "Betrag", "Notiz", "Tag",
    ]

    /// Kopfzeile der Projektsummen.
    public static let summaryHeader = [
        "Projekt", "Kunde", "Business/Privat", "Einträge", "Dauer (h:mm)", "Dauer (dezimal)",
        "Abrechenbar (dezimal)", "Stundensatz", "Betrag",
    ]

    /// Einzeleinträge, ein Eintrag je Zeile, nach Start sortiert.
    ///
    /// - „Dauer (h:mm)“ ist ungerundet (wie in der App), „Dauer (dezimal)“ in Stunden mit zwei
    ///   Nachkommastellen nach `rounding` (aufwärts je Eintrag).
    /// - „Stundensatz“: Satz des Projekts, sonst `defaultHourlyRate`; leer, wenn keiner gilt.
    /// - „Betrag“ nur für abrechenbare Einträge mit Stundensatz: gerundete Dauer × Satz, auf Cent.
    /// - Laufende Einträge: „Ende“ leer, Dauer bis `now`.
    /// - Einträge, deren Projekt fehlt, werden ausgelassen.
    public static func entries(
        _ entries: [TimeEntry],
        projects: [Project],
        rounding: Rounding,
        calendar: Calendar,
        defaultHourlyRate: Decimal? = nil,
        now: Date = .now
    ) -> String {
        let byId = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var lines = [line(entryHeader)]
        for entry in entries.sorted(by: { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }) {
            guard let project = byId[entry.projectId] else { continue }
            let duration = entry.duration(at: now)
            let rounded = rounding.apply(duration)
            let isBillable = entry.effectiveBillable(project: project)
            let rate = project.hourlyRate ?? defaultHourlyRate
            let amount: String
            if isBillable, let rate {
                amount = Money.germanString(Money.amount(seconds: rounded, rate: rate))
            } else {
                amount = ""
            }
            lines.append(line([
                dateString(entry.startedAt, calendar: calendar),
                timeString(entry.startedAt, calendar: calendar),
                entry.endedAt.map { timeString($0, calendar: calendar) } ?? "",
                DurationFormat.hourMinute(duration),
                decimalHours(rounded),
                project.name,
                project.client ?? "",
                project.isBusiness ? "Business" : "Privat",
                isBillable ? "ja" : "nein",
                rate.map { Money.germanString($0) } ?? "",
                amount,
                entry.nextStep ?? "",
                entry.tag ?? "",
            ]))
        }
        return byteOrderMark + lines.joined(separator: lineEnding) + lineEnding
    }

    /// Projektsummen eines Berichts: eine Zeile „Zeitraum“, eine Leerzeile, dann die Tabelle
    /// in Berichtsreihenfolge und eine Summenzeile.
    public static func summary(_ report: Report, calendar: Calendar = .current) -> String {
        var lines = [
            line(["Zeitraum", report.period.title(calendar: calendar)]),
            "",
            line(summaryHeader),
        ]
        for row in report.rows {
            lines.append(line([
                row.project.name,
                row.project.client ?? "",
                row.project.isBusiness ? "Business" : "Privat",
                String(row.entryCount),
                DurationFormat.hourMinute(row.duration),
                decimalHours(row.roundedDuration),
                decimalHours(row.roundedBillableDuration),
                row.hourlyRate.map { Money.germanString($0) } ?? "",
                row.amount.map { Money.germanString($0) } ?? "",
            ]))
        }
        lines.append(line([
            "Summe", "", "",
            String(report.rows.reduce(0) { $0 + $1.entryCount }),
            DurationFormat.hourMinute(report.total),
            decimalHours(report.roundedTotal),
            decimalHours(report.roundedBillable),
            "",
            Money.germanString(report.amount),
        ]))
        return byteOrderMark + lines.joined(separator: lineEnding) + lineEnding
    }

    // MARK: Bausteine

    /// Eine Zeile aus Feldern, jedes bei Bedarf escaped.
    static func line(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: separator)
    }

    /// Setzt ein Feld in Anführungszeichen, wenn es Trennzeichen, Anführungszeichen oder
    /// Zeilenumbrüche enthält.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Stunden mit zwei Nachkommastellen und Komma, z. B. 5400 s → „1,50“.
    static func decimalHours(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0,00" }
        let millis = Decimal(Int64((seconds * 1000).rounded()))
        return Money.germanString(millis / 3_600_000)
    }

    /// „20.10.2026“
    static func dateString(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.day, .month, .year], from: date)
        return String(format: "%02d.%02d.%04d", c.day ?? 0, c.month ?? 0, c.year ?? 0)
    }

    /// „09:05“
    static func timeString(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
