import Foundation

// Effektiver Stundensatz: Was eine Stunde investierter Zeit tatsächlich einbringt.
// Gerechnet wird `Betrag / gesamte Zeit` – auch nicht abrechenbare Zeit zählt mit (Akquise,
// interne Arbeit, gekappte Stunden). Der nominale Satz rechnet dagegen nur mit den
// abgerechneten (je Eintrag gerundeten) Stunden. Die Lücke zwischen beiden zeigt, wie viel
// Arbeit nicht bezahlt wird.

extension Money {
    /// Satz pro Stunde: `amount / (seconds / 3600)`, kaufmännisch auf Cent gerundet.
    /// `nil`, wenn Betrag oder Zeit 0 (bzw. ungültig) sind.
    public static func rate(amount: Decimal, seconds: TimeInterval) -> Decimal? {
        guard amount != 0, seconds.isFinite, seconds > 0 else { return nil }
        let millis = Decimal(Int64((seconds * 1000).rounded()))
        guard millis > 0 else { return nil }
        return round(amount * 3_600_000 / millis, scale: 2)
    }
}

extension ProjectReportRow {
    /// Betrag je Stunde gesamter Projektzeit (inkl. nicht abrechenbarer Zeit, ungerundet).
    /// `nil` ohne Betrag oder ohne Zeit.
    public var effectiveRate: Decimal? {
        Money.rate(amount: amount ?? 0, seconds: duration)
    }
}

extension ClientRow {
    /// Betrag je Stunde gesamter Kundenzeit (inkl. nicht abrechenbarer Zeit). `nil` ohne Betrag
    /// oder ohne Zeit.
    public var effectiveRate: Decimal? {
        Money.rate(amount: amount, seconds: duration)
    }
}

/// Gemeinsame Rechnung für `Report` und `YearReport`.
enum RateFigures {
    /// Gesamtbetrag je Stunde Business-Zeit.
    static func effectiveRate(amount: Decimal, business: TimeInterval) -> Decimal? {
        Money.rate(amount: amount, seconds: business)
    }

    /// Durchschnittlicher abgerechneter Satz: Beträge je gerundeter abrechenbarer Stunde, nur über
    /// Zeilen mit Stundensatz (Zeilen ohne Satz würden den Schnitt sonst drücken).
    static func nominalRate(_ rows: [ProjectReportRow]) -> Decimal? {
        let priced = rows.filter { $0.hourlyRate != nil && $0.roundedBillableDuration > 0 }
        let amount = priced.reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }
        return Money.rate(amount: amount, seconds: priced.reduce(0) { $0 + $1.roundedBillableDuration })
    }

    /// Anteil nicht abrechenbarer Zeit an der Zeit der Business-Projekte (ungerundet), 0…1.
    static func nonBillableShare(_ rows: [ProjectReportRow]) -> Double {
        let business = rows.filter(\.project.isBusiness)
        let total = business.reduce(0) { $0 + $1.duration }
        guard total > 0 else { return 0 }
        let billable = business.reduce(0) { $0 + $1.billableDuration }
        return min(1, max(0, (total - billable) / total))
    }

    /// Effektiver Satz liegt mehr als `threshold` (Standard 15 %) unter dem nominalen.
    static func isBelowNominal(effective: Decimal?, nominal: Decimal?, threshold: Double) -> Bool {
        guard let effective, let nominal, nominal > 0 else { return false }
        let e = NSDecimalNumber(decimal: effective).doubleValue
        let n = NSDecimalNumber(decimal: nominal).doubleValue
        return e < n * (1 - threshold)
    }
}

extension Report {
    /// Gesamtbetrag je Stunde Business-Zeit (Privatzeit ausgenommen, nicht abrechenbare
    /// Business-Zeit eingeschlossen). `nil` ohne Betrag oder ohne Business-Zeit.
    public var effectiveRate: Decimal? {
        RateFigures.effectiveRate(amount: amount, business: business)
    }

    /// Durchschnittlicher nominaler Satz: Betrag je abgerechneter (gerundeter) Stunde der
    /// Projekte mit Stundensatz. `nil` ohne Betrag.
    public var nominalRate: Decimal? { RateFigures.nominalRate(rows) }

    /// Anteil nicht abrechenbarer Zeit an der Business-Zeit (0…1, ungerundet); 0 ohne Business-Zeit.
    public var nonBillableShare: Double { RateFigures.nonBillableShare(rows) }

    /// Liegt der effektive Satz mehr als `threshold` unter dem nominalen? (Warnfarbe in den Berichten.)
    public func isEffectiveRateLow(threshold: Double = 0.15) -> Bool {
        RateFigures.isBelowNominal(effective: effectiveRate, nominal: nominalRate, threshold: threshold)
    }
}

extension YearReport {
    /// Gesamtbetrag je Stunde Business-Zeit des Jahres (wie `Report.effectiveRate`).
    public var effectiveRate: Decimal? {
        RateFigures.effectiveRate(amount: amount, business: business)
    }

    /// Durchschnittlicher nominaler Satz des Jahres (wie `Report.nominalRate`).
    public var nominalRate: Decimal? { RateFigures.nominalRate(byProject) }

    /// Anteil nicht abrechenbarer Zeit an der Business-Zeit des Jahres (0…1).
    public var nonBillableShare: Double { RateFigures.nonBillableShare(byProject) }

    /// Liegt der effektive Satz mehr als `threshold` unter dem nominalen?
    public func isEffectiveRateLow(threshold: Double = 0.15) -> Bool {
        RateFigures.isBelowNominal(effective: effectiveRate, nominal: nominalRate, threshold: threshold)
    }
}

extension ProjectReportRow {
    /// Effektiver Satz liegt mehr als `threshold` unter dem geltenden Stundensatz.
    public func isEffectiveRateLow(threshold: Double = 0.15) -> Bool {
        RateFigures.isBelowNominal(effective: effectiveRate, nominal: hourlyRate, threshold: threshold)
    }
}
