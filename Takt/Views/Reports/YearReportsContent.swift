import SwiftUI
import TaktCore

// Inhalt des Berichts-Reiters „Jahr“. Von oben nach unten:
//   Kennzahlen: Gesamt (± Vorjahr) · Abrechenbar · Umsatz (± Vorjahr) · Ø pro aktivem Tag.
//   Monate: 12 Balken, Umschalter „Stunden | Umsatz“ rechts darüber.
//   Kunden und „Wohin ging die Zeit“ (Tag-Anteile) – nebeneinander, im schmalen Fenster untereinander.
//   Projekte: Tabelle wie in den anderen Zeiträumen, aufgeklappt mit Monatsverlauf.
// Rein darstellend; Daten kommen als `YearReportsData`.

struct YearReportsContent: View {
    let data: YearReportsData
    let theme: DesignTheme
    /// Nur für das Render-Harness: aufgeklappte Projekte, überfahrener Monat, Diagramm-Modus.
    var initiallyExpanded: Set<UUID> = []
    var initialHover: Int?

    @State private var mode: YearChartMode
    @State private var width: CGFloat = 0

    /// Ab dieser Inhaltsbreite stehen Kunden und Tag-Anteile nebeneinander.
    private static let sideBySideWidth: CGFloat = 800

    init(data: YearReportsData, theme: DesignTheme, initiallyExpanded: Set<UUID> = [],
         initialHover: Int? = nil, initialMode: YearChartMode = .hours) {
        self.data = data
        self.theme = theme
        self.initiallyExpanded = initiallyExpanded
        self.initialHover = initialHover
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            YearReportsMetrics(data: data, theme: theme)
            monthsSection
            if width >= Self.sideBySideWidth {
                HStack(alignment: .top, spacing: 36) {
                    clientsSection
                        .frame(maxWidth: .infinity)
                    tagsSection
                        .frame(width: min(360, width * 0.4))
                }
            } else {
                clientsSection
                // Im schmalen Fenster nicht über die ganze Breite ziehen – Balken bleiben vergleichbar.
                tagsSection
                    .frame(maxWidth: 520, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Projekte")
                ReportsProjectTable(year: data, theme: theme, initiallyExpanded: initiallyExpanded)
                    .id(data.year)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
    }

    // MARK: Monate

    private var monthsSection: some View {
        let showsToggle = data.hasAnyRate
        let effectiveMode: YearChartMode = showsToggle ? mode : .hours
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 14) {
                sectionTitle("Monate")
                Spacer()
                if effectiveMode == .hours {
                    legend
                }
                if showsToggle {
                    YearChartModePicker(selection: $mode, theme: theme)
                }
            }
            YearReportsChart(data: data, mode: effectiveMode, theme: theme, initialHover: initialHover)
                // Neues Jahr → Hover zurücksetzen.
                .id("\(data.year)-\(effectiveMode.rawValue)")
        }
    }

    /// „● Business ● Privat“ – nur bei Stunden (beim Umsatz gibt es eine Reihe).
    private var legend: some View {
        HStack(spacing: 12) {
            legendItem("Business", color: .accentColor)
            legendItem("Privat", color: Color.secondary.opacity(0.55))
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(theme.tertiary)
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
        }
    }

    // MARK: Kunden

    private var clientsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Kunden")
            YearClientsTable(data: data, theme: theme)
        }
    }

    // MARK: Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Wohin ging die Zeit")
            YearTagShares(shares: data.report.tagShares, theme: theme)
        }
    }
}

// MARK: - Kennzahlen

/// Gesamt (± Vorjahr) · Abrechenbar · Umsatz (± Vorjahr) · Ø pro aktivem Tag · Effektiver Satz.
struct YearReportsMetrics: View {
    let data: YearReportsData
    let theme: DesignTheme

    @State private var width: CGFloat = 1_000

    private var report: YearReport { data.report }
    private var previousYear: String { String(data.year - 1) }

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

    /// Im schmalen Fenster steht „Effektiver Satz“ als Zeile unter den Kacheln.
    var body: some View {
        let inRow = width >= ReportsRateTile.minRowWidth
        VStack(alignment: .leading, spacing: 10) {
            tiles(rateInRow: inRow)
            if !inRow { rateFigures.row }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func tiles(rateInRow: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ReportsTile(title: "Gesamt", theme: theme) {
                ReportsBigNumber(text: ReportsFormat.duration(report.total), theme: theme)
            } caption: {
                delta(data.totalDelta, missing: "kein Vorjahr zum Vergleich")
            }
            .help("\(previousYear): \(ReportsFormat.duration(report.previousYearTotal))")

            ReportsTile(title: "Abrechenbar", theme: theme) {
                ReportsBigNumber(text: ReportsFormat.duration(data.roundedBillable), theme: theme)
            } caption: {
                Text(ReportsFormat.roundingHint(data.rounding))
            }

            ReportsTile(title: "Umsatz", theme: theme) {
                if data.hasAnyRate {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        ReportsBigNumber(text: ReportsFormat.money(report.amount), theme: theme)
                        Text(data.currencyCode)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.tertiary)
                    }
                } else {
                    ReportsBigNumber(text: "–", dimmed: true, theme: theme)
                }
            } caption: {
                if data.hasAnyRate {
                    delta(data.amountDelta, missing: "kein Vorjahresumsatz")
                } else {
                    Text("kein Stundensatz hinterlegt")
                }
            }
            .help("\(previousYear): \(ReportsFormat.money(report.previousYearAmount)) \(data.currencyCode)")

            ReportsTile(title: "Ø pro aktivem Tag", theme: theme) {
                ReportsBigNumber(text: ReportsFormat.duration(report.averagePerActiveDay), theme: theme)
            } caption: {
                Text(ReportsFormat.activeDays(report.activeDays))
            }

            if rateInRow {
                rateFigures
            }
        }
        // Alle Kacheln so hoch wie die höchste.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// „+12 % ggü. 2025“ – die Zahl etwas kräftiger, sonst leise.
    @ViewBuilder
    private func delta(_ fraction: Double?, missing: String) -> some View {
        if let fraction {
            HStack(spacing: 4) {
                // `Color.secondary` statt `.secondary`: sonst relativ zur leisen Beschriftung (noch blasser).
                Text(ReportsFormat.delta(fraction))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .monospacedDigit()
                Text("ggü. \(previousYear)")
            }
        } else {
            Text(missing)
        }
    }
}

// MARK: - Kunden

/// Kunde · Projekte · Stunden · Abrechenbar · Betrag · Eff. Satz, nach Betrag sortiert, mit Summenzeile.
struct YearClientsTable: View {
    let data: YearReportsData
    let theme: DesignTheme

    private enum Column {
        static let projects: CGFloat = 62
        static let hours: CGFloat = 64
        static let billable: CGFloat = 84
        static let amount: CGFloat = 92
        static let effective: CGFloat = 70
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(Array(data.report.byClient.enumerated()), id: \.offset) { _, client in
                Rectangle().fill(theme.hairline).frame(height: 1)
                row(client)
            }
            Rectangle().fill(theme.hairline).frame(height: 1)
            sumRow
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("Kunde").frame(maxWidth: .infinity, alignment: .leading)
            Text("Projekte").frame(width: Column.projects, alignment: .trailing)
            Text("Stunden").frame(width: Column.hours, alignment: .trailing)
            Text("Abrechenbar").frame(width: Column.billable, alignment: .trailing)
            Text("Betrag \(data.currencyCode)").frame(width: Column.amount, alignment: .trailing)
            Text("Eff. Satz")
                .frame(width: Column.effective, alignment: .trailing)
                .help(ReportsProjectTable.effectiveRateHelp)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(theme.tertiary)
        .lineLimit(1)
        .padding(.bottom, 8)
    }

    private func row(_ client: ClientRow) -> some View {
        let billable = data.roundedBillable(for: client)
        let hasAmount = data.hasAnyRate && client.amount > 0
        return HStack(spacing: 0) {
            Text(client.client ?? "ohne Kunde")
                .font(.system(size: 14, weight: client.client == nil ? .regular : .medium))
                .foregroundStyle(client.client == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(client.projectCount)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: Column.projects, alignment: .trailing)
            Text(ReportsFormat.duration(client.duration))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .frame(width: Column.hours, alignment: .trailing)
            Text(billable > 0 ? ReportsFormat.duration(billable) : "–")
                .font(.system(size: 13))
                .foregroundStyle(billable > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(theme.tertiary))
                .frame(width: Column.billable, alignment: .trailing)
            Text(hasAmount ? ReportsFormat.money(client.amount) : "–")
                .font(.system(size: 13, weight: hasAmount ? .semibold : .regular))
                .foregroundStyle(hasAmount ? AnyShapeStyle(.primary) : AnyShapeStyle(theme.tertiary))
                .frame(width: Column.amount, alignment: .trailing)
            effectiveCell(hasAmount ? client.effectiveRate : nil, weight: .regular)
        }
        .monospacedDigit()
        .lineLimit(1)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var sumRow: some View {
        HStack(spacing: 0) {
            Text("Summe")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(data.report.byProject.count)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: Column.projects, alignment: .trailing)
            Text(ReportsFormat.duration(data.report.total))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .frame(width: Column.hours, alignment: .trailing)
            Text(ReportsFormat.duration(data.roundedBillable))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: Column.billable, alignment: .trailing)
            Text(data.hasAnyRate ? ReportsFormat.money(data.report.amount) : "–")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(data.hasAnyRate ? AnyShapeStyle(.primary) : AnyShapeStyle(theme.tertiary))
                .frame(width: Column.amount, alignment: .trailing)
            effectiveCell(data.hasAnyRate ? data.report.effectiveRate : nil, weight: .semibold,
                          isLow: data.report.isEffectiveRateLow(),
                          help: "Betrag ÷ gesamte Business-Zeit inkl. nicht abrechenbar (ohne Privatzeit)")
        }
        .monospacedDigit()
        .lineLimit(1)
        .padding(.vertical, 12)
    }

    /// Effektiver Satz, dezent (Kunden haben oft mehrere Sätze – daher ohne Warnfarbe je Zeile).
    private func effectiveCell(_ rate: Decimal?, weight: Font.Weight, isLow: Bool = false,
                               help: String = ReportsProjectTable.effectiveRateHelp) -> some View {
        Text(rate.map(ReportsFormat.money) ?? "–")
            .font(.system(size: 12, weight: weight))
            .foregroundStyle(rate == nil ? AnyShapeStyle(theme.tertiary)
                             : isLow ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
            .frame(width: Column.effective, alignment: .trailing)
            .help(rate == nil ? "" : help)
    }
}

// MARK: - Tag-Anteile

/// Waagrechte Balken je Tag (die acht größten, „Sonstige“, „ohne Tag“) mit Dauer und Prozent.
/// Balkenlänge relativ zum größten Anteil, damit auch kleine Anteile lesbar bleiben.
struct YearTagShares: View {
    let shares: [TagShare]
    let theme: DesignTheme

    var body: some View {
        let largest = max(0.0001, shares.map(\.fraction).max() ?? 0)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
                if index > 0 {
                    Rectangle().fill(theme.hairline).frame(height: 1)
                }
                row(share, largest: largest)
            }
        }
        // Erste Haarlinie auf Höhe der Tabellenköpfe nebenan.
        .padding(.top, 2)
    }

    private func row(_ share: TagShare, largest: Double) -> some View {
        let isTag = share.tag != nil && !share.isOther
        return HStack(spacing: 12) {
            Text(share.title)
                .font(.system(size: 13, weight: isTag ? .medium : .regular))
                .foregroundStyle(isTag ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 96, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.track)
                    Capsule()
                        .fill(barStyle(share))
                        .frame(width: max(4, geo.size.width * share.fraction / largest))
                }
            }
            .frame(height: 6)
            Text(ReportsFormat.duration(share.duration))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(width: 52, alignment: .trailing)
            Text(ReportsFormat.percent(share.fraction))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
        .monospacedDigit()
        .frame(height: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(share.title): \(ReportsFormat.duration(share.duration)), \(ReportsFormat.percent(share.fraction))")
    }

    /// Tags in Akzentfarbe, „Sonstige“ und „ohne Tag“ grau.
    private func barStyle(_ share: TagShare) -> AnyShapeStyle {
        if share.isOther { return AnyShapeStyle(Color.secondary.opacity(0.45)) }
        if share.tag == nil { return AnyShapeStyle(Color.secondary.opacity(0.3)) }
        return AnyShapeStyle(Color.accentColor.opacity(0.85))
    }
}
