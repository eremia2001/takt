import Charts
import SwiftUI
import TaktCore

/// Gestapelte Balken je Tag (beim Tag: je Stunde, bei langen Zeiträumen: je Woche) in
/// Projektfarben. Achsen minimal, nur waagrechte Haarlinien. Beim Überfahren zeigt ein
/// Hinweis den Tag und die Summe. Freie Tage (Urlaub, Krank …) sind als schraffierte Spalte
/// hinterlegt.
struct ReportsChart: View {
    let data: ReportsData
    let theme: DesignTheme
    /// Vorbelegung für das Render-Harness (sonst setzt der Mauszeiger den Wert).
    var initialHover: Date?

    @State private var hovered: Date?

    init(data: ReportsData, theme: DesignTheme, initialHover: Date? = nil) {
        self.data = data
        self.theme = theme
        self.initialHover = initialHover
        _hovered = State(initialValue: initialHover)
    }

    /// Ein gestapeltes Teilstück.
    private struct Segment: Identifiable {
        let bucket: Date
        let projectKey: String
        let value: Double
        var id: String { "\(bucket.timeIntervalSinceReferenceDate)-\(projectKey)" }
    }

    var body: some View {
        let buckets = data.chartBuckets
        let unit = data.chartUnit
        let rows = data.report.rows
        let segments = Self.segments(buckets: buckets, rows: rows, unit: unit)
        let maxValue = buckets.map { Self.value($0.total, unit: unit) }.max() ?? 0
        let hoveredBucket = buckets.first { $0.start == hovered }

        Chart {
            ForEach(segments) { segment in
                BarMark(
                    x: .value("Zeit", segment.bucket, unit: unit.component, calendar: calendarFor(unit)),
                    y: .value("Dauer", segment.value),
                    width: .ratio(unit == .hour ? 0.78 : 0.62)
                )
                .foregroundStyle(by: .value("Projekt", segment.projectKey))
                .cornerRadius(2.5)
                .opacity(hovered == nil || hovered == segment.bucket ? 1 : 0.45)
            }
            if let hoveredBucket, hoveredBucket.total > 0 {
                PointMark(
                    x: .value("Zeit", hoveredBucket.start, unit: unit.component, calendar: calendarFor(unit)),
                    y: .value("Dauer", Self.value(hoveredBucket.total, unit: unit))
                )
                .symbolSize(0)
                .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    tooltip(hoveredBucket, unit: unit)
                }
            }
        }
        .chartForegroundStyleScale(
            domain: rows.map { $0.project.id.uuidString },
            range: rows.map { Color(hex: $0.project.colorHex) }
        )
        .chartLegend(.hidden)
        .chartYScale(domain: 0...Self.niceMax(maxValue, unit: unit))
        .chartXScale(domain: (buckets.first?.start ?? data.interval.start)...(buckets.last?.end ?? data.interval.end))
        .chartYAxis {
            AxisMarks(position: .leading, values: Self.yTicks(maxValue, unit: unit)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(theme.hairline)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(unit == .hour ? "\(Int(number)) min" : "\(Int(number)) h")
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(theme.tertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xLabelDates(buckets, unit: unit)) { value in
                AxisValueLabel(centered: false, anchor: .top, collisionResolution: .disabled) {
                    if let date = value.as(Date.self) {
                        Text(xLabel(date, unit: unit))
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(isToday(date, unit: unit) ? AnyShapeStyle(.primary) : AnyShapeStyle(theme.tertiary))
                    }
                }
            }
        }
        .chartBackground { proxy in
            if unit == .day {
                daysOffBackground(proxy: proxy, buckets: buckets)
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
                            guard let date: Date = proxy.value(atX: x) else { hovered = nil; return }
                            hovered = buckets.first { $0.start <= date && date < $0.end }?.start
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
        .padding(.top, 18)
        .frame(height: 190)
        .accessibilityLabel("Verlauf")
    }

    // MARK: Freie Tage

    /// Schraffierte Spalten hinter den Balken freier Tage, oben mit der Art („Urlaub“).
    private func daysOffBackground(proxy: ChartProxy, buckets: [ReportsData.ChartBucket]) -> some View {
        let daysOff = data.daysOffByDay
        let marked = buckets.compactMap { bucket in daysOff[bucket.start].map { (bucket, $0) } }
        return GeometryReader { geo in
            if let plotFrame = proxy.plotFrame {
                let frame = geo[plotFrame]
                ForEach(marked, id: \.0.start) { bucket, dayOff in
                    if let x1 = proxy.position(forX: bucket.start), let x2 = proxy.position(forX: bucket.end) {
                        let width = max(4, (x2 - x1) * 0.86)
                        VStack(spacing: 0) {
                            // Beschriftung nur, wenn die Spalte breit genug ist (Monat: nur Schraffur).
                            if width >= 44 {
                                Text(dayOff.kind.title)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(theme.tertiary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .padding(.top, 6)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(width: width, height: frame.height)
                        .background(HatchPattern(theme: theme))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .position(x: frame.minX + (x1 + x2) / 2, y: frame.midY)
                        .accessibilityLabel("\(ReportsFormat.tooltipDay(bucket.start, calendar: data.calendar)): \(dayOff.kind.title)")
                    }
                }
            }
        }
    }

    // MARK: Werte

    /// Stunden (bzw. Minuten in der Stundenansicht) als Diagrammwert.
    private static func value(_ seconds: TimeInterval, unit: ReportsData.ChartUnit) -> Double {
        unit == .hour ? seconds / 60 : seconds / 3600
    }

    /// Teilstücke je Balken in Reihenfolge der Projektzeilen (größtes Projekt unten).
    private static func segments(buckets: [ReportsData.ChartBucket], rows: [ProjectReportRow],
                                 unit: ReportsData.ChartUnit) -> [Segment] {
        buckets.flatMap { bucket in
            rows.compactMap { row -> Segment? in
                guard let seconds = bucket.perProject[row.project.id], seconds > 0 else { return nil }
                return Segment(bucket: bucket.start, projectKey: row.project.id.uuidString, value: value(seconds, unit: unit))
            }
        }
    }

    /// Glatte Obergrenze der y-Achse mit etwas Luft für den Hinweis.
    private static func niceMax(_ value: Double, unit: ReportsData.ChartUnit) -> Double {
        if unit == .hour { return 60 }
        let step = tickStep(value)
        return max(step, ((value * 1.08) / step).rounded(.up) * step)
    }

    private static func tickStep(_ value: Double) -> Double {
        switch value {
        case ..<4: 1
        case ..<10: 2
        case ..<24: 4
        case ..<60: 10
        default: 20
        }
    }

    private static func yTicks(_ value: Double, unit: ReportsData.ChartUnit) -> [Double] {
        if unit == .hour { return [0, 30, 60] }
        let step = tickStep(value)
        return Array(stride(from: 0, through: niceMax(value, unit: unit), by: step))
    }

    private func calendarFor(_ unit: ReportsData.ChartUnit) -> Calendar {
        unit == .week ? data.isoCalendar : data.calendar
    }

    // MARK: Beschriftung

    /// Beschriftete Balken: alle bei wenigen, sonst jeder n-te (Monat: 1., 8., 15., …).
    /// Die Beschriftung sitzt in der Balkenmitte (`centered: true` würde zwischen zwei
    /// Beschriftungen zentrieren und bei Lücken verrutschen).
    private func xLabelDates(_ buckets: [ReportsData.ChartBucket], unit: ReportsData.ChartUnit) -> [Date] {
        let every: Int
        switch unit {
        case .hour: every = 2
        case .day: every = buckets.count <= 14 ? 1 : 7
        case .week: every = max(1, Int((Double(buckets.count) / 10).rounded(.up)))
        }
        return buckets.enumerated()
            .filter { $0.offset % every == 0 }
            .map { $0.element.start.addingTimeInterval($0.element.end.timeIntervalSince($0.element.start) / 2) }
    }

    private func xLabel(_ date: Date, unit: ReportsData.ChartUnit) -> String {
        let calendar = data.calendar
        switch unit {
        case .hour:
            return String(format: "%02d", calendar.component(.hour, from: date))
        case .day:
            if data.chartBuckets.count <= 7 { return ReportsFormat.shortDay(date, calendar: calendar) }
            if data.chartBuckets.count <= 14 {
                return "\(ReportsFormat.weekdaysShort[calendar.component(.weekday, from: date) - 1]) \(calendar.component(.day, from: date))."
            }
            let c = calendar.dateComponents([.day, .month], from: date)
            return "\(c.day ?? 0).\(c.month ?? 0)."
        case .week:
            return "KW \(data.isoCalendar.component(.weekOfYear, from: date))"
        }
    }

    private func isToday(_ date: Date, unit: ReportsData.ChartUnit) -> Bool {
        unit == .day && data.calendar.isDate(date, inSameDayAs: data.now)
    }

    private func tooltip(_ bucket: ReportsData.ChartBucket, unit: ReportsData.ChartUnit) -> some View {
        let calendar = data.calendar
        let title: String
        switch unit {
        case .hour:
            let hour = calendar.component(.hour, from: bucket.start)
            title = String(format: "%02d–%02d Uhr", hour, hour + 1)
        case .day:
            title = ReportsFormat.tooltipDay(bucket.start, calendar: calendar)
                + (data.daysOffByDay[bucket.start].map { " · \($0.kind.title)" } ?? "")
        case .week:
            title = "KW \(data.isoCalendar.component(.weekOfYear, from: bucket.start))"
        }
        return HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(ReportsFormat.duration(bucket.total))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(theme.surface, in: Capsule())
        .overlay(Capsule().stroke(theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(theme.dark ? 0.3 : 0.08), radius: 6, y: 2)
        .fixedSize()
    }
}

/// Leise Schraffur (diagonale Linien auf `track`) für freie Tage im Diagramm.
struct HatchPattern: View {
    let theme: DesignTheme

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(theme.track))
            let spacing: CGFloat = 7
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(theme.dark ? .white.opacity(0.11) : .black.opacity(0.09)), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}
