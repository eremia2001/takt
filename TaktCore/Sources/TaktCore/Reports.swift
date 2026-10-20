import Foundation
import GRDB

// MARK: - Zeitraum

/// Zeitraum eines Berichts. Wochen beginnen immer montags (ISO 8601, KW-Zählung wie in Deutschland),
/// unabhängig von den Einstellungen des übergebenen Kalenders.
public enum ReportPeriod: Hashable, Sendable {
    /// Der Kalendertag, in dem das Datum liegt.
    case day(Date)
    /// Die Woche (Montag bis Sonntag), in der das Datum liegt.
    case week(Date)
    /// Der Kalendermonat, in dem das Datum liegt.
    case month(Date)
    /// Frei gewählter Zeitraum; das Ende ist exklusiv.
    case custom(DateInterval)

    /// Halboffenes Intervall `[start, end)` des Zeitraums.
    public func interval(calendar: Calendar) -> DateInterval {
        switch self {
        case .day(let date):
            return calendar.dateInterval(of: .day, for: date)
                ?? DateInterval(start: calendar.startOfDay(for: date), duration: 24 * 3600)
        case .week(let date):
            let iso = Self.isoWeekCalendar(calendar)
            return iso.dateInterval(of: .weekOfYear, for: date)
                ?? DateInterval(start: iso.startOfDay(for: date), duration: 7 * 24 * 3600)
        case .month(let date):
            return calendar.dateInterval(of: .month, for: date)
                ?? DateInterval(start: calendar.startOfDay(for: date), duration: 30 * 24 * 3600)
        case .custom(let interval):
            return interval
        }
    }

    /// Deutscher Titel, z. B. „Dienstag, 20. Oktober 2026“, „KW 43 · 19.–25. Okt. 2026“,
    /// „Oktober 2026“, „1.–15. Okt. 2026“.
    public func title(calendar: Calendar) -> String {
        let range = interval(calendar: calendar)
        switch self {
        case .day(let date):
            let c = calendar.dateComponents([.weekday, .day, .month, .year], from: date)
            return "\(GermanDate.weekdays[(c.weekday ?? 1) - 1]), \(c.day ?? 0). \(GermanDate.months[(c.month ?? 1) - 1]) \(c.year ?? 0)"
        case .week(let date):
            let iso = Self.isoWeekCalendar(calendar)
            let week = iso.component(.weekOfYear, from: date)
            return "KW \(week) · " + GermanDate.dayRange(range, calendar: calendar)
        case .month(let date):
            let c = calendar.dateComponents([.month, .year], from: date)
            return "\(GermanDate.months[(c.month ?? 1) - 1]) \(c.year ?? 0)"
        case .custom:
            return GermanDate.dayRange(range, calendar: calendar)
        }
    }

    /// Vorheriger Zeitraum gleicher Art. Freie Zeiträume verschieben sich um ihre eigene Länge.
    public func previous(calendar: Calendar) -> ReportPeriod { shifted(by: -1, calendar: calendar) }

    /// Nächster Zeitraum gleicher Art. Freie Zeiträume verschieben sich um ihre eigene Länge.
    public func next(calendar: Calendar) -> ReportPeriod { shifted(by: 1, calendar: calendar) }

    private func shifted(by direction: Int, calendar: Calendar) -> ReportPeriod {
        // Immer vom Anfang des Zeitraums aus rechnen: robust bei Monatsenden (31. → 30.).
        let start = interval(calendar: calendar).start
        switch self {
        case .day:
            return .day(calendar.date(byAdding: .day, value: direction, to: start) ?? start)
        case .week:
            return .week(calendar.date(byAdding: .day, value: 7 * direction, to: start) ?? start)
        case .month:
            return .month(calendar.date(byAdding: .month, value: direction, to: start) ?? start)
        case .custom(let interval):
            // Ganze Tage (von Mitternacht zu Mitternacht) per Kalender verschieben, damit eine
            // Zeitumstellung die Grenzen nicht verschiebt; sonst um die exakte Dauer.
            let startOfDay = calendar.startOfDay(for: interval.start)
            let endOfDay = calendar.startOfDay(for: interval.end)
            if startOfDay == interval.start, endOfDay == interval.end,
               let days = calendar.dateComponents([.day], from: interval.start, to: interval.end).day, days > 0,
               let newStart = calendar.date(byAdding: .day, value: days * direction, to: interval.start),
               let newEnd = calendar.date(byAdding: .day, value: days * direction, to: interval.end) {
                return .custom(DateInterval(start: newStart, end: newEnd))
            }
            let offset = interval.duration * Double(direction)
            return .custom(DateInterval(start: interval.start.addingTimeInterval(offset), duration: interval.duration))
        }
    }

    /// Kopie des Kalenders mit Montag als Wochenbeginn und ISO-Wochenzählung (KW 1 = Woche mit
    /// dem ersten Donnerstag). Zeitzone bleibt erhalten.
    static func isoWeekCalendar(_ calendar: Calendar) -> Calendar {
        var iso = calendar
        iso.firstWeekday = 2
        iso.minimumDaysInFirstWeek = 4
        return iso
    }
}

/// Feste deutsche Namen – bewusst unabhängig von der Systemsprache und von ICU-Versionen.
enum GermanDate {
    static let weekdays = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
    static let months = ["Januar", "Februar", "März", "April", "Mai", "Juni",
                         "Juli", "August", "September", "Oktober", "November", "Dezember"]
    static let shortMonths = ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni",
                              "Juli", "Aug.", "Sept.", "Okt.", "Nov.", "Dez."]

    /// Tagesspanne eines halboffenen Intervalls: „1.–15. Okt. 2026“, „26. Okt.–1. Nov. 2026“,
    /// „29. Dez. 2025–4. Jan. 2026“, ein einzelner Tag als „15. Okt. 2026“.
    static func dayRange(_ interval: DateInterval, calendar: Calendar) -> String {
        let first = calendar.dateComponents([.day, .month, .year], from: interval.start)
        // Letzter enthaltener Tag: Ende exklusiv, deshalb knapp davor.
        let lastDate = interval.end > interval.start ? interval.end.addingTimeInterval(-1) : interval.start
        let last = calendar.dateComponents([.day, .month, .year], from: lastDate)
        let (d1, m1, y1) = (first.day ?? 0, first.month ?? 1, first.year ?? 0)
        let (d2, m2, y2) = (last.day ?? 0, last.month ?? 1, last.year ?? 0)

        if d1 == d2, m1 == m2, y1 == y2 {
            return "\(d1). \(shortMonths[m1 - 1]) \(y1)"
        }
        if y1 != y2 {
            return "\(d1). \(shortMonths[m1 - 1]) \(y1)–\(d2). \(shortMonths[m2 - 1]) \(y2)"
        }
        if m1 != m2 {
            return "\(d1). \(shortMonths[m1 - 1])–\(d2). \(shortMonths[m2 - 1]) \(y2)"
        }
        return "\(d1).–\(d2). \(shortMonths[m2 - 1]) \(y2)"
    }
}

// MARK: - Rundung

/// Rundung abrechenbarer Zeiten. Es wird immer **aufwärts** auf die Schrittweite gerundet,
/// und zwar je Eintrag (nach dem Zuschneiden auf den Zeitraum), nicht erst auf die Summe.
public enum Rounding: String, CaseIterable, Codable, Sendable {
    case none
    case minutes6
    case minutes15
    case minutes30

    /// Schrittweite in Sekunden; `nil` = keine Rundung.
    public var step: TimeInterval? {
        switch self {
        case .none: nil
        case .minutes6: 6 * 60
        case .minutes15: 15 * 60
        case .minutes30: 30 * 60
        }
    }

    /// Name in den Einstellungen.
    public var title: String {
        switch self {
        case .none: "Keine"
        case .minutes6: "6 Minuten (0,1 h)"
        case .minutes15: "15 Minuten"
        case .minutes30: "30 Minuten"
        }
    }

    /// Rundet auf die nächste volle Schrittweite auf. 0 bleibt 0, negative/ungültige Werte werden 0.
    /// Eine Toleranz von 1 ms fängt Gleitkomma-Rauschen ab (6:00,0000001 min bleibt 6 min).
    public func apply(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        guard let step else { return seconds }
        let steps = ((seconds - 0.001) / step).rounded(.up)
        return max(1, steps) * step
    }
}

// MARK: - Bericht

/// Zeit eines Projekts mit einem bestimmten Tag (bzw. ohne Tag), ungerundet.
public struct TagReportRow: Hashable, Sendable {
    /// `nil` = Einträge ohne Tag („ohne Tag“).
    public var tag: String?
    public var duration: TimeInterval
    public var entryCount: Int

    public init(tag: String?, duration: TimeInterval, entryCount: Int) {
        self.tag = tag
        self.duration = duration
        self.entryCount = entryCount
    }
}

/// Eine Zeile je Projekt mit Zeit im Zeitraum.
public struct ProjectReportRow: Hashable, Sendable {
    public var project: Project
    /// Auf den Zeitraum zugeschnittene Zeit, ungerundet.
    public var duration: TimeInterval
    /// Summe der je Eintrag gerundeten Zeiten.
    public var roundedDuration: TimeInterval
    public var entryCount: Int
    /// Abrechenbarer Anteil, ungerundet.
    public var billableDuration: TimeInterval
    /// Abrechenbarer Anteil, je Eintrag gerundet – Grundlage für `amount`.
    public var roundedBillableDuration: TimeInterval
    /// Geltender Stundensatz: der des Projekts, sonst der Standard-Stundensatz; `nil` = keiner.
    public var hourlyRate: Decimal?
    /// `roundedBillableDuration / 3600 × hourlyRate`, auf Cent gerundet; `nil` ohne Stundensatz.
    public var amount: Decimal?
    /// Aufteilung nach Tag (Tags genau wie gespeichert, `nil` = ohne Tag), nach Dauer absteigend.
    public var byTag: [TagReportRow]

    public init(
        project: Project,
        duration: TimeInterval,
        roundedDuration: TimeInterval,
        entryCount: Int,
        billableDuration: TimeInterval,
        roundedBillableDuration: TimeInterval,
        hourlyRate: Decimal?,
        amount: Decimal?,
        byTag: [TagReportRow] = []
    ) {
        self.project = project
        self.duration = duration
        self.roundedDuration = roundedDuration
        self.entryCount = entryCount
        self.billableDuration = billableDuration
        self.roundedBillableDuration = roundedBillableDuration
        self.hourlyRate = hourlyRate
        self.amount = amount
        self.byTag = byTag
    }
}

/// Fortschritt zum Wochenziel (nur in Wochenberichten).
public struct GoalProgress: Hashable, Sendable {
    /// Wochenziel aus den Einstellungen (für eine volle Woche mit fünf Arbeitstagen).
    public var target: TimeInterval
    /// Abrechenbare Zeit der Woche, ungerundet.
    public var achieved: TimeInterval
    /// Ziel anteilig für die Arbeitstage der Woche: `target × workdays / 5`.
    public var adjustedTarget: TimeInterval
    /// `achieved / adjustedTarget`, nicht gedeckelt (über 1 = Ziel übertroffen). Ohne
    /// Arbeitstage (`adjustedTarget == 0`) gilt das Ziel als erreicht: 1.
    public var fraction: Double

    public init(target: TimeInterval, achieved: TimeInterval, adjustedTarget: TimeInterval, fraction: Double) {
        self.target = target
        self.achieved = achieved
        self.adjustedTarget = adjustedTarget
        self.fraction = fraction
    }

    /// Noch fehlende Zeit bis zum angepassten Ziel, nie negativ.
    public var remaining: TimeInterval { max(0, adjustedTarget - achieved) }
}

/// Zeit eines Kalendertags, aufgeteilt nach Projekt (ungerundet).
public struct DayBucket: Hashable, Sendable {
    /// Beginn des Tages (Mitternacht im Berichtskalender).
    public var day: Date
    public var perProject: [UUID: TimeInterval]

    public init(day: Date, perProject: [UUID: TimeInterval]) {
        self.day = day
        self.perProject = perProject
    }

    public var total: TimeInterval { perProject.values.reduce(0, +) }
}

/// Auswertung eines Zeitraums. Alle Dauern sind auf den Zeitraum zugeschnitten; laufende
/// Einträge zählen bis `now`.
public struct Report: Hashable, Sendable {
    public var period: ReportPeriod
    public var interval: DateInterval
    /// Gesamtzeit, ungerundet.
    public var total: TimeInterval
    /// Gesamtzeit, je Eintrag gerundet.
    public var roundedTotal: TimeInterval
    /// Zeit auf Business-Projekten (ungerundet).
    public var business: TimeInterval
    /// Zeit auf Privat-Projekten (ungerundet).
    public var personal: TimeInterval
    /// Abrechenbare Zeit, ungerundet.
    public var billable: TimeInterval
    /// Abrechenbare Zeit, je Eintrag gerundet.
    public var roundedBillable: TimeInterval
    /// Summe der Beträge aller Zeilen mit Stundensatz.
    public var amount: Decimal
    /// Nach Dauer absteigend (bei Gleichstand in Projektreihenfolge).
    public var rows: [ProjectReportRow]
    /// Ein Eintrag je Kalendertag des Zeitraums, lückenlos und aufsteigend.
    public var days: [DayBucket]
    public var focus: FocusStats
    /// Tage mit mehr als 0 Sekunden erfasster Zeit.
    public var activeDays: Int
    /// `total / activeDays`, 0 ohne aktive Tage.
    public var averagePerActiveDay: TimeInterval
    /// Als frei markierte Tage im Zeitraum, nach Datum.
    public var daysOff: [DayOff]
    /// Arbeitstage: Montag bis Freitag im Zeitraum, ohne freie Tage.
    public var workdays: Int
    /// `total / workdays`, 0 ohne Arbeitstage.
    public var averagePerWorkday: TimeInterval
    /// Wochenziel; nur bei `.week` und gesetztem Ziel, sonst `nil`.
    public var goal: GoalProgress?

    public init(
        period: ReportPeriod,
        interval: DateInterval,
        total: TimeInterval,
        roundedTotal: TimeInterval,
        business: TimeInterval,
        personal: TimeInterval,
        billable: TimeInterval,
        roundedBillable: TimeInterval,
        amount: Decimal,
        rows: [ProjectReportRow],
        days: [DayBucket],
        focus: FocusStats,
        activeDays: Int,
        averagePerActiveDay: TimeInterval,
        daysOff: [DayOff] = [],
        workdays: Int = 0,
        averagePerWorkday: TimeInterval = 0,
        goal: GoalProgress? = nil
    ) {
        self.period = period
        self.interval = interval
        self.total = total
        self.roundedTotal = roundedTotal
        self.business = business
        self.personal = personal
        self.billable = billable
        self.roundedBillable = roundedBillable
        self.amount = amount
        self.rows = rows
        self.days = days
        self.focus = focus
        self.activeDays = activeDays
        self.averagePerActiveDay = averagePerActiveDay
        self.daysOff = daysOff
        self.workdays = workdays
        self.averagePerWorkday = averagePerWorkday
        self.goal = goal
    }
}

extension AppDatabase {
    /// Erstellt den Bericht für einen Zeitraum in einer Leseabfrage.
    /// - Parameters:
    ///   - rounding: Rundung je Eintrag (aufwärts) für `rounded…`-Werte und Beträge.
    ///   - defaultHourlyRate: Satz für Projekte ohne eigenen Stundensatz.
    ///   - weeklyGoal: Wochenziel in Sekunden (`nil`/≤ 0 = keins); wirkt nur bei `.week`.
    public func report(
        for period: ReportPeriod,
        rounding: Rounding,
        defaultHourlyRate: Decimal? = nil,
        weeklyGoal: TimeInterval? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> Report {
        let interval = period.interval(calendar: calendar)
        let (projects, entries, daysOff) = try writer.read { db in
            (try Project.fetchAll(db), try Self.entries(db, in: interval),
             try Self.daysOff(db, in: interval, calendar: calendar))
        }
        return Self.makeReport(
            period: period, interval: interval, projects: projects, entries: entries,
            rounding: rounding, defaultHourlyRate: defaultHourlyRate, daysOff: daysOff,
            weeklyGoal: weeklyGoal, now: now, calendar: calendar
        )
    }

    /// Reine Berechnung (ohne Datenbank), erwartet Einträge nach Start sortiert.
    static func makeReport(
        period: ReportPeriod,
        interval: DateInterval,
        projects: [Project],
        entries: [TimeEntry],
        rounding: Rounding,
        defaultHourlyRate: Decimal?,
        daysOff: [DayOff] = [],
        weeklyGoal: TimeInterval? = nil,
        now: Date,
        calendar: Calendar
    ) -> Report {
        let byId = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let order = Dictionary(projects.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })

        // Lückenlose Tagesliste des Zeitraums.
        var dayStarts: [Date] = []
        var cursor = calendar.startOfDay(for: interval.start)
        while cursor < interval.end {
            dayStarts.append(cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor), nextDay > cursor else { break }
            cursor = nextDay
        }
        var perDay: [[UUID: TimeInterval]] = Array(repeating: [:], count: dayStarts.count)

        struct Accumulator {
            var duration: TimeInterval = 0
            var rounded: TimeInterval = 0
            var count = 0
            var billable: TimeInterval = 0
            var roundedBillable: TimeInterval = 0
            var tags: [String?: (duration: TimeInterval, count: Int)] = [:]
        }
        var accumulators: [UUID: Accumulator] = [:]
        var business: TimeInterval = 0
        var personal: TimeInterval = 0
        var usedEntries: [TimeEntry] = []

        for entry in entries {
            guard let project = byId[entry.projectId] else { continue }
            usedEntries.append(entry)
            let range = clippedRange(entry, to: interval, now: now)
            let duration = range.end.timeIntervalSince(range.start)
            let rounded = rounding.apply(duration)
            let isBillable = entry.effectiveBillable(project: project)

            var acc = accumulators[project.id, default: Accumulator()]
            acc.duration += duration
            acc.rounded += rounded
            acc.count += 1
            let tagPart = acc.tags[entry.tag, default: (0, 0)]
            acc.tags[entry.tag] = (tagPart.duration + duration, tagPart.count + 1)
            if isBillable {
                acc.billable += duration
                acc.roundedBillable += rounded
            }
            accumulators[project.id] = acc
            if project.isBusiness { business += duration } else { personal += duration }

            // Auf die Tage verteilen (Einträge über Mitternacht zählen anteilig).
            guard duration > 0 else { continue }
            for (index, dayStart) in dayStarts.enumerated() {
                let dayEnd = index + 1 < dayStarts.count ? dayStarts[index + 1] : interval.end
                if dayEnd <= range.start { continue }
                if dayStart >= range.end { break }
                let part = min(dayEnd, range.end).timeIntervalSince(max(dayStart, range.start))
                if part > 0 { perDay[index][project.id, default: 0] += part }
            }
        }

        var rows: [ProjectReportRow] = accumulators.compactMap { id, acc in
            guard let project = byId[id] else { return nil }
            let rate = project.hourlyRate ?? defaultHourlyRate
            return ProjectReportRow(
                project: project,
                duration: acc.duration,
                roundedDuration: acc.rounded,
                entryCount: acc.count,
                billableDuration: acc.billable,
                roundedBillableDuration: acc.roundedBillable,
                hourlyRate: rate,
                amount: rate.map { Money.amount(seconds: acc.roundedBillable, rate: $0) },
                byTag: Self.tagRows(acc.tags)
            )
        }
        rows.sort { a, b in
            if a.duration != b.duration { return a.duration > b.duration }
            return (order[a.project.id] ?? 0) < (order[b.project.id] ?? 0)
        }

        let total = rows.reduce(0) { $0 + $1.duration }
        let days = zip(dayStarts, perDay).map { DayBucket(day: $0, perProject: $1) }
        let activeDays = days.filter { $0.total > 0 }.count

        // Arbeitstage: Mo–Fr (Wochentag 2…6 im gregorianischen Sinn) ohne freie Tage.
        let daysOffKeys = Set(daysOff.map(\.date))
        let workdays = dayStarts.filter { day in
            let weekday = calendar.component(.weekday, from: day)
            return (2...6).contains(weekday) && !daysOffKeys.contains(DayOff.key(for: day, calendar: calendar))
        }.count
        let billable = rows.reduce(0) { $0 + $1.billableDuration }

        var goal: GoalProgress?
        if case .week = period, let target = weeklyGoal, target > 0 {
            let adjusted = target * Double(workdays) / 5
            goal = GoalProgress(
                target: target,
                achieved: billable,
                adjustedTarget: adjusted,
                fraction: adjusted > 0 ? billable / adjusted : 1
            )
        }

        return Report(
            period: period,
            interval: interval,
            total: total,
            roundedTotal: rows.reduce(0) { $0 + $1.roundedDuration },
            business: business,
            personal: personal,
            billable: billable,
            roundedBillable: rows.reduce(0) { $0 + $1.roundedBillableDuration },
            amount: rows.reduce(Decimal(0)) { $0 + ($1.amount ?? 0) },
            rows: rows,
            days: days,
            focus: focusStats(for: usedEntries, in: interval, now: now),
            activeDays: activeDays,
            averagePerActiveDay: activeDays > 0 ? total / Double(activeDays) : 0,
            daysOff: daysOff,
            workdays: workdays,
            averagePerWorkday: workdays > 0 ? total / Double(workdays) : 0,
            goal: goal
        )
    }

    /// Tag-Zeilen nach Dauer absteigend; bei Gleichstand alphabetisch, „ohne Tag“ zuletzt.
    private static func tagRows(_ tags: [String?: (duration: TimeInterval, count: Int)]) -> [TagReportRow] {
        tags.map { TagReportRow(tag: $0.key, duration: $0.value.duration, entryCount: $0.value.count) }
            .sorted { a, b in
                if a.duration != b.duration { return a.duration > b.duration }
                switch (a.tag, b.tag) {
                case let (x?, y?): return x.localizedStandardCompare(y) == .orderedAscending
                case (_?, nil): return true
                default: return false
                }
            }
    }
}

// MARK: - Geldbeträge

/// Rechenhilfen für Beträge. Gerechnet wird mit `Decimal`, gerundet kaufmännisch auf Cent.
public enum Money {
    /// `seconds / 3600 × rate`, kaufmännisch auf zwei Nachkommastellen gerundet.
    public static func amount(seconds: TimeInterval, rate: Decimal) -> Decimal {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        // Sekunden auf Millisekunden begrenzen, damit das Double sauber in Decimal übergeht.
        let millis = Decimal(Int64((seconds * 1000).rounded()))
        let raw = millis * rate / 3_600_000
        return round(raw, scale: 2)
    }

    /// Kaufmännisches Runden (`.plain`) auf `scale` Nachkommastellen.
    public static func round(_ value: Decimal, scale: Int) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }

    /// Feste Schreibweise mit Dezimalkomma und genau `fractionDigits` Stellen, ohne
    /// Tausendertrennung: „85,00“, „1234,50“, „-3,10“.
    public static func germanString(_ value: Decimal, fractionDigits: Int = 2) -> String {
        let rounded = round(value, scale: fractionDigits)
        let posix = NSDecimalNumber(decimal: rounded).description(withLocale: Locale(identifier: "en_US_POSIX"))
        let negative = posix.hasPrefix("-")
        let digits = negative ? String(posix.dropFirst()) : posix
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        let integer = parts.first.map(String.init) ?? "0"
        var fraction = parts.count > 1 ? String(parts[1]) : ""
        if fraction.count < fractionDigits {
            fraction += String(repeating: "0", count: fractionDigits - fraction.count)
        }
        let body = fractionDigits > 0 ? "\(integer),\(fraction)" : integer
        return (negative && rounded != 0 ? "-" : "") + body
    }

    /// Liest eine Zahl in deutscher oder englischer Schreibweise („85“, „85,5“, „85.50“,
    /// „1.234,50“). Leerzeichen, Währungszeichen und `€` werden ignoriert; ungültig → `nil`.
    public static func parse(_ text: String) -> Decimal? {
        var cleaned = text.filter { $0.isNumber || $0 == "," || $0 == "." || $0 == "-" }
        guard !cleaned.isEmpty else { return nil }
        if cleaned.contains(",") {
            // Deutsch: Punkte sind Tausendertrenner, Komma ist Dezimaltrenner.
            cleaned = cleaned.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        }
        guard cleaned.filter({ $0 == "." }).count <= 1 else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }
}
