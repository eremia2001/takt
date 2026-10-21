import Foundation

// Tätigkeitsnachweis (Timesheet) für Kunden: Einträge eines Zeitraums, gefiltert nach Kunde oder
// Projekt, mit Rundung je Eintrag wie im CSV-Export (Satz des Projekts, sonst Standardsatz).
// Der Betrag je Satz rechnet mit der Summe der gerundeten Zeiten (`Stunden × Satz`, auf Cent), damit
// die Zeile „42,75 h × 95,00 €“ auf dem Nachweis genau aufgeht; die Zeilenbeträge (je Eintrag auf
// Cent) können davon um Cent abweichen. Reine Berechnung ohne Datenbank – die App liefert Einträge
// und Projekte, die PDF-Erzeugung liegt in der App (`TimesheetPDF`).

/// Welche Einträge ein Timesheet enthält.
public enum TimesheetScope: Hashable, Sendable {
    /// Alle Projekte.
    case all
    /// Alle Projekte eines Kunden (Vergleich getrimmt, ohne Groß-/Kleinschreibung und Akzente).
    case client(String)
    /// Ein einzelnes Projekt.
    case project(UUID)
}

/// Optionen, die die Zahlen beeinflussen (Darstellung wie Notizen/Tags regelt das PDF).
public struct TimesheetOptions: Hashable, Sendable {
    /// Nur abrechenbare Einträge aufnehmen.
    public var billableOnly: Bool
    /// Rundung je Eintrag für die Dezimalstunden und Beträge; `.none` = exakt.
    public var rounding: Rounding

    public init(billableOnly: Bool = true, rounding: Rounding = .none) {
        self.billableOnly = billableOnly
        self.rounding = rounding
    }
}

/// Eine Zeile des Nachweises (ein Eintrag, auf den Zeitraum zugeschnitten).
public struct TimesheetLine: Hashable, Sendable, Identifiable {
    /// ID des Eintrags.
    public var id: UUID
    public var start: Date
    public var end: Date
    public var project: Project
    /// Notiz („Nächster Schritt“) des Eintrags, getrimmt; `nil` = keine.
    public var note: String?
    public var tag: String?
    /// Zugeschnittene Dauer, ungerundet.
    public var duration: TimeInterval
    /// Dauer nach `TimesheetOptions.rounding` (aufwärts je Eintrag).
    public var billedDuration: TimeInterval
    public var isBillable: Bool
    /// Satz des Projekts, sonst Standardsatz; `nil` = keiner.
    public var hourlyRate: Decimal?
    /// `billedDuration × hourlyRate` auf Cent – nur für abrechenbare Einträge mit Satz.
    public var amount: Decimal?

    public init(
        id: UUID, start: Date, end: Date, project: Project, note: String?, tag: String?,
        duration: TimeInterval, billedDuration: TimeInterval, isBillable: Bool,
        hourlyRate: Decimal?, amount: Decimal?
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.project = project
        self.note = note
        self.tag = tag
        self.duration = duration
        self.billedDuration = billedDuration
        self.isBillable = isBillable
        self.hourlyRate = hourlyRate
        self.amount = amount
    }
}

/// Zeilen eines Kalendertags (nach Beginn des Eintrags) mit Tagessumme.
public struct TimesheetDay: Hashable, Sendable {
    /// Mitternacht des Tages.
    public var day: Date
    public var lines: [TimesheetLine]

    public init(day: Date, lines: [TimesheetLine]) {
        self.day = day
        self.lines = lines
    }

    public var duration: TimeInterval { lines.reduce(0) { $0 + $1.duration } }
    public var billedDuration: TimeInterval { lines.reduce(0) { $0 + $1.billedDuration } }
}

/// Abgerechnete Stunden und Betrag zu einem Stundensatz.
public struct TimesheetRateGroup: Hashable, Sendable {
    public var rate: Decimal
    /// Gerundete Zeit der abrechenbaren Einträge mit diesem Satz.
    public var billedDuration: TimeInterval
    /// `billedDuration / 3600 × rate`, auf Cent.
    public var amount: Decimal

    public init(rate: Decimal, billedDuration: TimeInterval, amount: Decimal) {
        self.rate = rate
        self.billedDuration = billedDuration
        self.amount = amount
    }
}

public struct Timesheet: Hashable, Sendable {
    public var interval: DateInterval
    public var scope: TimesheetScope
    public var options: TimesheetOptions
    /// Chronologisch (Beginn, dann ID).
    public var lines: [TimesheetLine]
    /// Nach Tag gruppiert, aufsteigend; nur Tage mit Zeilen.
    public var days: [TimesheetDay]
    /// Abgerechnete Zeit und Betrag je Stundensatz (höchster Satz zuerst).
    public var rateGroups: [TimesheetRateGroup]
    /// Laufende Einträge im Zeitraum, die nicht aufgenommen wurden.
    public var excludedRunning: [TimeEntry]

    public init(
        interval: DateInterval, scope: TimesheetScope, options: TimesheetOptions,
        lines: [TimesheetLine], days: [TimesheetDay], rateGroups: [TimesheetRateGroup],
        excludedRunning: [TimeEntry]
    ) {
        self.interval = interval
        self.scope = scope
        self.options = options
        self.lines = lines
        self.days = days
        self.rateGroups = rateGroups
        self.excludedRunning = excludedRunning
    }

    public var isEmpty: Bool { lines.isEmpty }
    /// Erfasste Zeit aller Zeilen, ungerundet.
    public var totalDuration: TimeInterval { lines.reduce(0) { $0 + $1.duration } }
    /// Abgerechnete (gerundete) Zeit aller Zeilen.
    public var totalBilledDuration: TimeInterval { lines.reduce(0) { $0 + $1.billedDuration } }
    /// Gerundete Zeit der abrechenbaren Zeilen.
    public var billableBilledDuration: TimeInterval {
        lines.filter(\.isBillable).reduce(0) { $0 + $1.billedDuration }
    }
    /// Gerundete Zeit abrechenbarer Zeilen ohne Stundensatz.
    public var billableWithoutRate: TimeInterval {
        lines.filter { $0.isBillable && $0.hourlyRate == nil }.reduce(0) { $0 + $1.billedDuration }
    }
    /// Enthält nicht abrechenbare Zeilen.
    public var hasNonBillable: Bool { lines.contains { !$0.isBillable } }
    /// Summe der Beträge; `nil`, wenn keine abrechenbare Zeile einen Satz hat.
    public var amount: Decimal? {
        rateGroups.isEmpty ? nil : rateGroups.reduce(Decimal(0)) { $0 + $1.amount }
    }
    /// Der eine Stundensatz, wenn alle abgerechneten Zeilen denselben haben; sonst `nil`.
    public var hourlyRate: Decimal? { rateGroups.count == 1 ? rateGroups[0].rate : nil }
    /// Mehr als ein Projekt in den Zeilen.
    public var hasSeveralProjects: Bool { Set(lines.map(\.project.id)).count > 1 }

    /// Deutscher Titel des Zeitraums: „Oktober 2026“ für einen ganzen Kalendermonat, sonst
    /// die Tagesspanne („1.–15. Okt. 2026“).
    public func periodTitle(calendar: Calendar) -> String {
        if let month = calendar.dateInterval(of: .month, for: interval.start), month == interval {
            return ReportPeriod.month(interval.start).title(calendar: calendar)
        }
        return GermanDate.dayRange(interval, calendar: calendar)
    }

    /// Stellt das Timesheet zusammen.
    /// - Parameters:
    ///   - entries: Einträge, die sich mit `interval` überschneiden (Reihenfolge egal).
    ///   - projects: alle Projekte (auch archivierte); Einträge ohne Projekt fallen weg.
    ///   - now: laufende Einträge werden nie aufgenommen, sondern in `excludedRunning` gemeldet.
    public static func make(
        entries: [TimeEntry],
        projects: [Project],
        interval: DateInterval,
        scope: TimesheetScope,
        options: TimesheetOptions,
        defaultHourlyRate: Decimal?,
        calendar: Calendar
    ) -> Timesheet {
        let byId = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var lines: [TimesheetLine] = []
        var running: [TimeEntry] = []

        for entry in entries {
            guard let project = byId[entry.projectId], matches(project, scope: scope) else { continue }
            let isBillable = entry.effectiveBillable(project: project)
            if options.billableOnly, !isBillable { continue }
            guard let endedAt = entry.endedAt else {
                if entry.startedAt < interval.end { running.append(entry) }
                continue
            }
            let start = max(entry.startedAt, interval.start)
            let end = min(endedAt, interval.end)
            guard end > start else { continue }

            let duration = end.timeIntervalSince(start)
            let billed = options.rounding.apply(duration)
            let rate = project.hourlyRate ?? defaultHourlyRate
            let note = entry.nextStep?.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append(TimesheetLine(
                id: entry.id, start: start, end: end, project: project,
                note: (note?.isEmpty ?? true) ? nil : note,
                tag: entry.tag,
                duration: duration, billedDuration: billed, isBillable: isBillable,
                hourlyRate: rate,
                amount: isBillable ? rate.map { Money.amount(seconds: billed, rate: $0) } : nil
            ))
        }
        lines.sort { ($0.start, $0.id.uuidString) < ($1.start, $1.id.uuidString) }

        var days: [TimesheetDay] = []
        for line in lines {
            let day = calendar.startOfDay(for: line.start)
            if days.last?.day == day {
                days[days.count - 1].lines.append(line)
            } else {
                days.append(TimesheetDay(day: day, lines: [line]))
            }
        }

        var billedByRate: [Decimal: TimeInterval] = [:]
        for line in lines where line.isBillable {
            guard let rate = line.hourlyRate else { continue }
            billedByRate[rate, default: 0] += line.billedDuration
        }
        let groups = billedByRate.map { rate, seconds in
            TimesheetRateGroup(rate: rate, billedDuration: seconds, amount: Money.amount(seconds: seconds, rate: rate))
        }

        return Timesheet(
            interval: interval,
            scope: scope,
            options: options,
            lines: lines,
            days: days,
            rateGroups: groups.sorted { $0.rate > $1.rate },
            excludedRunning: running.sorted { $0.startedAt < $1.startedAt }
        )
    }

    /// Gehört das Projekt zum Umfang?
    public static func matches(_ project: Project, scope: TimesheetScope) -> Bool {
        switch scope {
        case .all: return true
        case .project(let id): return project.id == id
        case .client(let name):
            guard let client = normalizedClient(project.client) else { return false }
            return AppDatabase.foldedForSearch(client) == AppDatabase.foldedForSearch(name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Kundennamen der Projekte, ohne Dubletten (gleiche Zusammenfassung wie im Jahresbericht,
    /// die erste Schreibweise gewinnt), alphabetisch.
    public static func clients(of projects: [Project]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for project in projects {
            guard let client = normalizedClient(project.client) else { continue }
            if seen.insert(AppDatabase.foldedForSearch(client)).inserted { result.append(client) }
        }
        return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func normalizedClient(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
