import SwiftUI
import TaktCore

/// Kennzahlen-Reihe: Gesamt · Business/Privat · Abrechenbar · Umsatz, in Woche und Monat dazu
/// „Effektiver Satz“.
/// Dezente Kacheln, große Zahl, kleine Beschriftung. In der Woche mit Wochenziel darunter
/// eine schmale Zeile mit dem Fortschritt.
struct ReportsMetrics: View {
    let data: ReportsData
    let theme: DesignTheme

    @State private var width: CGFloat = 1_000

    private var report: Report { data.report }

    /// Kachel „Effektiver Satz“ in der Reihe – im schmalen Fenster als Zeile darunter.
    private var rateInRow: Bool { width >= ReportsRateTile.minRowWidth }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            tiles
            if data.showsRateTile, !rateInRow {
                rateFigures.row
            }
            if let goal = report.goal {
                ReportsGoalRow(goal: goal, workdays: report.workdays, theme: theme)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var rateFigures: ReportsRateTile {
        ReportsRateTile(
            effective: report.effectiveRate,
            nominal: report.nominalRate,
            nonBillableShare: report.nonBillableShare,
            isLow: report.isEffectiveRateLow(),
            hasAnyRate: data.hasAnyRate,
            currencyCode: data.currencyCode,
            theme: theme
        )
    }

    private var tiles: some View {
        HStack(alignment: .top, spacing: 12) {
            tile("Gesamt", help: "Alle erfasste Zeit im Zeitraum, ungerundet – Business und Privat zusammen.") {
                bigNumber(ReportsFormat.duration(report.total))
            } caption: {
                Text(entryCountText)
            }

            tile("Business · Privat", help: "Business-Zeit / Privatzeit. Die Art legst du im Projekt fest; der Balken zeigt den Business-Anteil.") {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    bigNumber(ReportsFormat.duration(report.business))
                    Text("/ \(ReportsFormat.duration(report.personal))")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.tertiary)
                        .lineLimit(1)
                }
            } caption: {
                splitBar
            }

            tile("Abrechenbar", help: TermHelp.billable) {
                bigNumber(ReportsFormat.duration(report.roundedBillable))
            } caption: {
                Text(ReportsFormat.roundingHint(data.rounding))
            }

            tile("Umsatz", help: "Abrechenbare Stunden × Stundensatz je Projekt (sonst Standard-Stundensatz aus Einstellungen › Abrechnung).") {
                if data.hasAnyRate {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        bigNumber(ReportsFormat.money(report.amount))
                        Text(data.currencyCode)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.tertiary)
                    }
                } else {
                    bigNumber("–", dimmed: true)
                }
            } caption: {
                Text(revenueCaption)
            }

            if data.showsRateTile, rateInRow {
                rateFigures
            }
        }
        // Alle Kacheln so hoch wie die höchste.
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Bausteine

    private func tile<Value: View, Caption: View>(
        _ title: String,
        help: String? = nil,
        @ViewBuilder value: () -> Value,
        @ViewBuilder caption: () -> Caption
    ) -> some View {
        ReportsTile(title: title, theme: theme, help: help, value: value, caption: caption)
    }

    private func bigNumber(_ text: String, dimmed: Bool = false) -> some View {
        ReportsBigNumber(text: text, dimmed: dimmed, theme: theme)
    }

    /// Anteil Business (kräftig) zu Privat (zart) – farblos, Farbe gehört den Projekten.
    private var splitBar: some View {
        let total = report.business + report.personal
        let share = total > 0 ? report.business / total : 0
        return GeometryReader { geo in
            HStack(spacing: 2) {
                if share > 0 {
                    Capsule().fill(.primary.opacity(0.55))
                        .frame(width: max(4, geo.size.width * share - (share < 1 ? 1 : 0)))
                }
                if share < 1 {
                    Capsule().fill(theme.track)
                }
            }
        }
        .frame(height: 5)
        .padding(.vertical, 4)
        .accessibilityLabel("Business-Anteil \(Int((share * 100).rounded())) Prozent")
    }

    private var entryCountText: String {
        let count = report.rows.reduce(0) { $0 + $1.entryCount }
        return count == 1 ? "1 Eintrag" : "\(count) Einträge"
    }

    private var revenueCaption: String {
        guard data.hasAnyRate else { return "kein Stundensatz hinterlegt" }
        let missing = data.billableRowsWithoutRate.count
        if missing == 1 { return "1 Projekt ohne Satz" }
        if missing > 1 { return "\(missing) Projekte ohne Satz" }
        return "für \(ReportsFormat.duration(report.roundedBillable)) h"
    }
}

/// „Wochenziel 25:36 von 32:00 (4 Arbeitstage) · 80 %“ mit schmalem Fortschrittsbalken.
/// Projektneutral in der Akzentfarbe; ab 100 % grün. Das Ziel ist schon um freie Tage gekürzt.
struct ReportsGoalRow: View {
    let goal: GoalProgress
    let workdays: Int
    let theme: DesignTheme

    private var isReached: Bool { goal.fraction >= 1 }
    private var barColor: Color { isReached ? .green : .accentColor }

    var body: some View {
        HStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Wochenziel")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.tertiary)
                Text(ReportsFormat.duration(goal.achieved))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("von \(ReportsFormat.duration(goal.adjustedTarget))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("(\(ReportsFormat.workdays(workdays)))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.tertiary)
            }
            .lineLimit(1)
            .fixedSize()

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.track)
                    Capsule()
                        .fill(barColor)
                        .frame(width: goal.fraction > 0 ? max(5, geo.size.width * min(1, goal.fraction)) : 0)
                }
            }
            .frame(height: 5)
            .frame(minWidth: 60)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if isReached {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                } else {
                    Text("noch \(ReportsFormat.duration(goal.remaining))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.tertiary)
                }
                Text(ReportsFormat.percent(goal.fraction))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(isReached ? AnyShapeStyle(Color.green) : AnyShapeStyle(.primary))
            }
            .lineLimit(1)
            .fixedSize()
        }
        .monospacedDigit()
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.hairline, lineWidth: 1))
        .help(TermHelp.weeklyGoal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wochenziel \(ReportsFormat.duration(goal.achieved)) von \(ReportsFormat.duration(goal.adjustedTarget)), \(ReportsFormat.percent(goal.fraction))")
    }
}

/// Kachel der Kennzahlen-Reihe: kleine Überschrift, große Zahl, leise Beschriftung darunter.
/// Gemeinsam für alle Zeiträume und das Jahr.
struct ReportsTile<Value: View, Caption: View>: View {
    let title: String
    let theme: DesignTheme
    /// Tooltip: was die Kennzahl bedeutet.
    var help: String?
    let value: Value
    let caption: Caption

    init(title: String, theme: DesignTheme, help: String? = nil,
         @ViewBuilder value: () -> Value, @ViewBuilder caption: () -> Caption) {
        self.title = title
        self.theme = theme
        self.help = help
        self.value = value()
        self.caption = caption()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.tertiary)
                .lineLimit(1)
            value
                .padding(.top, 4)
            // Beschriftungen aller Kacheln auf einer Linie, auch wenn eine Zahl kleiner skaliert.
            Spacer(minLength: 0)
            caption
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.top, 6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.hairline, lineWidth: 1))
        .help(help ?? "")
        .accessibilityElement(children: .combine)
    }
}

/// Große Zahl einer Kachel (gerundete Schrift, Ziffern gleich breit).
struct ReportsBigNumber: View {
    let text: String
    var dimmed = false
    /// Warnfarbe statt Primärfarbe (z. B. effektiver Satz deutlich unter dem nominalen).
    var tint: Color?
    let theme: DesignTheme

    var body: some View {
        Text(text)
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(dimmed ? AnyShapeStyle(theme.tertiary)
                             : tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// Kachel „Effektiver Satz“: große Zahl „87,50 €/h“, darunter „nominal 95,00 · 9 % nicht
/// abrechenbar“ (zweizeilig, wenn die Kachel schmal ist). Liegt der effektive Satz mehr als
/// 15 % unter dem nominalen Durchschnitt, steht die Zahl in Orange. Gemeinsam für Woche, Monat
/// und Jahr.
struct ReportsRateTile: View {
    /// Betrag ÷ Business-Zeit (inkl. nicht abrechenbar); `nil` ohne Betrag.
    let effective: Decimal?
    /// Betrag ÷ abgerechnete Stunden der Projekte mit Satz.
    let nominal: Decimal?
    let nonBillableShare: Double
    let isLow: Bool
    let hasAnyRate: Bool
    let currencyCode: String
    let theme: DesignTheme

    static let help = "Effektiver Satz: Betrag ÷ gesamte Business-Zeit inkl. nicht abrechenbarer Zeit "
        + "(Privatzeit ausgenommen) – was eine Stunde Arbeit tatsächlich einbringt. "
        + "Nominal: Betrag ÷ abgerechnete Stunden. Orange: mehr als 15 % unter nominal."

    /// Ab dieser Breite der Kennzahlen-Reihe passt die Kachel als fünfte daneben; darunter wird
    /// sie zur schmalen Zeile (`row`), damit die anderen Zahlen nicht abgeschnitten werden.
    static let minRowWidth: CGFloat = 820

    /// Schmale Zeile unter den Kacheln: „Effektiver Satz  70,91 €/h   nominal 84,64 · 17 % nicht abrechenbar“.
    var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Effektiver Satz")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.tertiary)
            if let effective {
                Text("\(ReportsFormat.money(effective)) \(ReportsFormat.currencySymbol(currencyCode))/h")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(isLow ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.primary))
                Text("\(nominalText) · \(shareText)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Text(hasAnyRate ? "kein Umsatz im Zeitraum" : "kein Stundensatz hinterlegt")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .monospacedDigit()
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.hairline, lineWidth: 1))
        .help(Self.help)
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        ReportsTile(title: "Effektiver Satz", theme: theme) {
            if let effective {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    ReportsBigNumber(text: ReportsFormat.money(effective), tint: isLow ? .orange : nil, theme: theme)
                    Text("\(ReportsFormat.currencySymbol(currencyCode))/h")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
            } else {
                ReportsBigNumber(text: "–", dimmed: true, theme: theme)
            }
        } caption: {
            if effective != nil {
                ViewThatFits(in: .horizontal) {
                    Text("\(nominalText) · \(shareText)")
                        .fixedSize()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(nominalText)
                        Text(shareText)
                    }
                }
            } else {
                Text(hasAnyRate ? "kein Umsatz im Zeitraum" : "kein Stundensatz hinterlegt")
            }
        }
        .help(Self.help)
    }

    private var nominalText: String {
        nominal.map { "nominal \(ReportsFormat.money($0))" } ?? "nominal –"
    }

    private var shareText: String {
        "\(ReportsFormat.percent(nonBillableShare)) nicht abrechenbar"
    }
}
