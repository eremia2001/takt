import SwiftUI
import TaktCore

/// Kennzahlen-Reihe: Gesamt · Business/Privat · Abrechenbar · Umsatz.
/// Dezente Kacheln, große Zahl, kleine Beschriftung.
struct ReportsMetrics: View {
    let data: ReportsData
    let theme: DesignTheme

    private var report: Report { data.report }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            tile("Gesamt") {
                bigNumber(ReportsFormat.duration(report.total))
            } caption: {
                Text(entryCountText)
            }

            tile("Business · Privat") {
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

            tile("Abrechenbar") {
                bigNumber(ReportsFormat.duration(report.roundedBillable))
            } caption: {
                Text(ReportsFormat.roundingHint(data.rounding))
            }

            tile("Umsatz") {
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
        }
        // Alle Kacheln so hoch wie die höchste.
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Bausteine

    private func tile<Value: View, Caption: View>(
        _ title: String,
        @ViewBuilder value: () -> Value,
        @ViewBuilder caption: () -> Caption
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.tertiary)
                .lineLimit(1)
            value()
                .padding(.top, 4)
            caption()
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
        .accessibilityElement(children: .combine)
    }

    private func bigNumber(_ text: String, dimmed: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(dimmed ? AnyShapeStyle(theme.tertiary) : AnyShapeStyle(.primary))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
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
