import Charts
import SwiftUI
import TaktCore

/// Was das Monatsdiagramm zeigt.
enum YearChartMode: String, CaseIterable, Identifiable {
    case hours, revenue

    var id: Self { self }

    var title: String {
        switch self {
        case .hours: "Stunden"
        case .revenue: "Umsatz"
        }
    }
}

/// Zwölf Monatsbalken: Stunden gestapelt nach Business (Akzent) und Privat (`.secondary`) oder
/// Umsatz einfarbig. Der laufende Monat liegt auf einer leisen Fläche und ist kräftig
/// beschriftet, künftige Monate sind blass. Beim Überfahren: Monat und Wert.
struct YearReportsChart: View {
    let data: YearReportsData
    let mode: YearChartMode
    let theme: DesignTheme

    @State private var hovered: Int?

    init(data: YearReportsData, mode: YearChartMode, theme: DesignTheme, initialHover: Int? = nil) {
        self.data = data
        self.mode = mode
        self.theme = theme
        _hovered = State(initialValue: initialHover)
    }

    /// Ein Teilstück eines Balkens.
    private struct Segment: Identifiable {
        let month: Int
        let series: String
        let value: Double
        var id: String { "\(month)-\(series)" }
    }

    private static let business = "Business"
    private static let personal = "Privat"
    private static let revenue = "Umsatz"

    var body: some View {
        let months = data.report.months
        let segments = self.segments(months)
        let totals = months.map { value(of: $0) }
        let step = Self.tickStep(totals.max() ?? 0, mode: mode)
        let top = Self.niceMax(totals.max() ?? 0, step: step)
        let ticks = Array(stride(from: 0, through: top + step / 1000, by: step))

        Chart {
            if let current = data.currentMonthIndex {
                // Leise Fläche hinter dem laufenden Monat.
                RectangleMark(
                    x: .value("Monat", Self.label(current)),
                    yStart: .value("Wert", 0),
                    yEnd: .value("Wert", top),
                    width: .ratio(0.92)
                )
                .foregroundStyle(theme.track)
                .cornerRadius(6)
            }
            ForEach(segments) { segment in
                BarMark(
                    x: .value("Monat", Self.label(segment.month)),
                    y: .value("Wert", segment.value),
                    width: .ratio(0.56)
                )
                .foregroundStyle(by: .value("Reihe", segment.series))
                .cornerRadius(3)
                .opacity(opacity(for: segment.month))
            }
            if let hovered, months.indices.contains(hovered), totals[hovered] > 0 {
                PointMark(
                    x: .value("Monat", Self.label(hovered)),
                    y: .value("Wert", totals[hovered])
                )
                .symbolSize(0)
                .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    tooltip(months[hovered], index: hovered)
                }
            }
        }
        .chartForegroundStyleScale(
            domain: [Self.business, Self.personal, Self.revenue],
            range: [Color.accentColor, Color.secondary.opacity(0.55), Color.accentColor]
        )
        .chartLegend(.hidden)
        .chartXScale(domain: (0..<12).map(Self.label))
        .chartYScale(domain: 0...top)
        .chartYAxis {
            AxisMarks(position: .leading, values: ticks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(theme.hairline)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(axisLabel(number))
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(theme.tertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: (0..<12).map(Self.label)) { value in
                AxisValueLabel(centered: true, collisionResolution: .disabled) {
                    if let label = value.as(String.self), let index = Self.index(of: label) {
                        Text(label)
                            .font(.system(size: 10, weight: index == data.currentMonthIndex ? .bold : .medium))
                            .foregroundStyle(labelStyle(index))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plotFrame = proxy.plotFrame else { return }
                            let x = location.x - geo[plotFrame].minX
                            hovered = proxy.value(atX: x, as: String.self).flatMap(Self.index(of:))
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
        .padding(.top, 18)
        .frame(height: 210)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(months))
    }

    // MARK: Werte

    private func value(of month: MonthBucket) -> Double {
        switch mode {
        case .hours: (month.business + month.personal) / 3600
        case .revenue: NSDecimalNumber(decimal: month.amount).doubleValue
        }
    }

    /// Business unten, Privat oben; beim Umsatz ein Teilstück je Monat.
    private func segments(_ months: [MonthBucket]) -> [Segment] {
        months.enumerated().flatMap { index, month -> [Segment] in
            switch mode {
            case .hours:
                return [
                    Segment(month: index, series: Self.business, value: month.business / 3600),
                    Segment(month: index, series: Self.personal, value: month.personal / 3600),
                ].filter { $0.value > 0 }
            case .revenue:
                let amount = NSDecimalNumber(decimal: month.amount).doubleValue
                return amount > 0 ? [Segment(month: index, series: Self.revenue, value: amount)] : []
            }
        }
    }

    private func opacity(for index: Int) -> Double {
        if let hovered { return hovered == index ? 1 : 0.45 }
        return data.isFuture(index) ? 0.35 : 1
    }

    private func labelStyle(_ index: Int) -> AnyShapeStyle {
        if index == data.currentMonthIndex { return AnyShapeStyle(.primary) }
        return AnyShapeStyle(theme.tertiary.opacity(data.isFuture(index) ? 0.45 : 1))
    }

    /// Glatte Obergrenze mit etwas Luft für den Hinweis.
    static func niceMax(_ value: Double, step: Double) -> Double {
        max(step, ((value * 1.1) / step).rounded(.up) * step)
    }

    /// Schrittweite der y-Achse für etwa vier Linien (1–2–2,5–5 × 10ⁿ).
    static func tickStep(_ value: Double, mode: YearChartMode) -> Double {
        let minimum: Double = mode == .hours ? 1 : 10
        let raw = max(minimum, value / 4)
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let nice: Double = normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 2.5 ? 2.5 : normalized <= 5 ? 5 : 10
        return nice * magnitude
    }

    private func axisLabel(_ number: Double) -> String {
        switch mode {
        case .hours: "\(ReportsFormat.grouped(number)) h"
        case .revenue: "\(ReportsFormat.grouped(number)) \(ReportsFormat.currencySymbol(data.currencyCode))"
        }
    }

    // MARK: Beschriftung

    static func label(_ index: Int) -> String { ReportsFormat.monthsShort[index] }

    static func index(of label: String) -> Int? { ReportsFormat.monthsShort.firstIndex(of: label) }

    private func tooltip(_ month: MonthBucket, index: Int) -> some View {
        HStack(spacing: 6) {
            Text("\(ReportsFormat.monthsLong[index]) \(String(data.year))")
                .foregroundStyle(.secondary)
            switch mode {
            case .hours:
                Text(ReportsFormat.duration(month.business + month.personal))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                if month.business > 0, month.personal > 0 {
                    Text("Business \(ReportsFormat.duration(month.business)) · Privat \(ReportsFormat.duration(month.personal))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.tertiary)
                }
            case .revenue:
                Text("\(ReportsFormat.money(month.amount)) \(data.currencyCode)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
        }
        .monospacedDigit()
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(theme.surface, in: Capsule())
        .overlay(Capsule().stroke(theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(theme.dark ? 0.3 : 0.08), radius: 6, y: 2)
        .fixedSize()
    }

    private func accessibilitySummary(_ months: [MonthBucket]) -> String {
        let parts = months.enumerated().compactMap { index, month -> String? in
            guard !data.isFuture(index) else { return nil }
            switch mode {
            case .hours:
                return "\(ReportsFormat.monthsLong[index]) \(ReportsFormat.duration(month.business + month.personal))"
            case .revenue:
                return "\(ReportsFormat.monthsLong[index]) \(ReportsFormat.money(month.amount)) \(data.currencyCode)"
            }
        }
        return "Monate, \(mode.title): " + parts.joined(separator: ", ")
    }
}

/// Kleines Segment „Stunden | Umsatz“ rechts über dem Diagramm (wie die Zeitraum-Auswahl, kleiner).
struct YearChartModePicker: View {
    @Binding var selection: YearChartMode
    let theme: DesignTheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(YearChartMode.allCases) { mode in
                let isSelected = mode == selection
                Button {
                    selection = mode
                } label: {
                    Text(mode.title)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(isSelected ? theme.track : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Diagramm zeigt")
    }
}
