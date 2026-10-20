import SwiftUI
import TaktCore

/// Tabelle je Projekt mit Summenzeile. Ein Klick auf eine Zeile klappt die Aufschlüsselung
/// nach Tag (sofern Tags vergeben sind) und die Einträge des Projekts im Zeitraum auf.
struct ReportsProjectTable: View {
    let data: ReportsData
    let theme: DesignTheme

    @State private var expanded: Set<UUID>
    @State private var hoveredRow: UUID?

    init(data: ReportsData, theme: DesignTheme, initiallyExpanded: Set<UUID> = []) {
        self.data = data
        self.theme = theme
        _expanded = State(initialValue: initiallyExpanded)
    }

    /// Feste Spaltenbreiten; der Name nimmt den Rest.
    private enum Column {
        static let kind: CGFloat = 62
        static let count: CGFloat = 54
        static let duration: CGFloat = 58
        static let rounded: CGFloat = 66
        static let billable: CGFloat = 84
        static let rate: CGFloat = 70
        static let amount: CGFloat = 92
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(data.report.rows, id: \.project.id) { row in
                Rectangle().fill(theme.hairline).frame(height: 1)
                projectRow(row)
                if expanded.contains(row.project.id) {
                    entryRows(for: row)
                        .transition(.opacity)
                }
            }
            Rectangle().fill(theme.hairline).frame(height: 1)
            sumRow
        }
    }

    // MARK: Kopf

    private var header: some View {
        HStack(spacing: 0) {
            Text("Projekt")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 17)
            Text("Art").frame(width: Column.kind, alignment: .leading)
            Text("Einträge").frame(width: Column.count, alignment: .trailing)
            Text("Dauer").frame(width: Column.duration, alignment: .trailing)
            Text("Gerundet").frame(width: Column.rounded, alignment: .trailing)
            Text("Abrechenbar").frame(width: Column.billable, alignment: .trailing)
            Text("Satz").frame(width: Column.rate, alignment: .trailing)
            Text("Betrag \(data.currencyCode)").frame(width: Column.amount, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(theme.tertiary)
        .lineLimit(1)
        .padding(.bottom, 8)
    }

    // MARK: Projektzeile

    private func projectRow(_ row: ProjectReportRow) -> some View {
        let id = row.project.id
        let isExpanded = expanded.contains(id)
        let color = Color(hex: row.project.colorHex)
        let hasAmount = row.amount != nil && row.roundedBillableDuration > 0
        // Satz nur zeigen, wo er zählt: bei abrechenbarer Zeit oder eigenem Projektsatz.
        let shownRate = (row.roundedBillableDuration > 0 || row.project.hourlyRate != nil) ? row.hourlyRate : nil
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                if isExpanded { expanded.remove(id) } else { expanded.insert(id) }
            }
        } label: {
            HStack(spacing: 0) {
                HStack(spacing: 14) {
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: row.project.client == nil ? 18 : 32)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(row.project.name)
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(theme.tertiary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        }
                        if let client = row.project.client {
                            Text(client)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(row.project.isBusiness ? "Business" : "Privat")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: Column.kind, alignment: .leading)
                number("\(row.entryCount)", width: Column.count, style: .secondary)
                Text(ReportsFormat.duration(row.duration))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: Column.duration, alignment: .trailing)
                number(ReportsFormat.duration(row.roundedDuration), width: Column.rounded, style: .secondary)
                number(row.roundedBillableDuration > 0 ? ReportsFormat.duration(row.roundedBillableDuration) : "–",
                       width: Column.billable,
                       style: row.roundedBillableDuration > 0 ? .secondary : .tertiary)
                number(shownRate.map(ReportsFormat.money) ?? "–", width: Column.rate,
                       style: shownRate == nil ? .tertiary : .secondary)
                Text(hasAmount ? ReportsFormat.money(row.amount ?? 0) : "–")
                    .font(.system(size: 13, weight: hasAmount ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(hasAmount ? AnyShapeStyle(.primary) : AnyShapeStyle(theme.tertiary))
                    .frame(width: Column.amount, alignment: .trailing)
            }
            .lineLimit(1)
            .padding(.vertical, row.project.client == nil ? 10 : 8)
            .background(alignment: .center) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hoveredRow == id ? theme.track : .clear)
                    .padding(.horizontal, -8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hoveredRow = id } else if hoveredRow == id { hoveredRow = nil }
        }
        .help(isExpanded ? "Einträge zuklappen" : "Einträge anzeigen")
        .accessibilityElement(children: .combine)
        .accessibilityHint(isExpanded ? "Einträge zuklappen" : "Einträge anzeigen")
    }

    private enum NumberStyle { case primary, secondary, tertiary }

    private func number(_ text: String, width: CGFloat, style: NumberStyle) -> some View {
        Text(text)
            .font(.system(size: 13))
            .monospacedDigit()
            .foregroundStyle(style == .primary ? AnyShapeStyle(.primary)
                             : style == .secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(theme.tertiary))
            .frame(width: width, alignment: .trailing)
    }

    // MARK: Einträge (aufgeklappt)

    private func entryRows(for row: ProjectReportRow) -> some View {
        let entries = data.entries(for: row.project.id)
        return VStack(alignment: .leading, spacing: 0) {
            if data.hasTags(row) {
                tagBreakdown(row)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
            }
            ForEach(entries) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(ReportsFormat.shortDay(entry.startedAt, calendar: data.calendar))
                        .foregroundStyle(.secondary)
                        .frame(width: 68, alignment: .leading)
                    Text("\(ReportsFormat.clock(entry.startedAt)) – \(entry.endedAt.map(ReportsFormat.clock) ?? "jetzt")")
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                    Text(ReportsFormat.duration(data.clippedDuration(entry)))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(width: 40, alignment: .trailing)
                    if entry.isRunning {
                        Text("läuft")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: row.project.colorHex))
                    }
                    if let tag = entry.tag {
                        TagCapsule(tag: tag)
                    }
                    Text(entry.nextStep ?? "")
                        .foregroundStyle(theme.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 12))
                .monospacedDigit()
                .padding(.vertical, 4)
            }
        }
        .padding(.leading, 17)
        .padding(.top, 2)
        .padding(.bottom, 10)
    }

    /// „nach Tag“: je Tag ein Balken mit Anteil an der Projektzeit; „ohne Tag“ grau und zuletzt.
    private func tagBreakdown(_ row: ProjectReportRow) -> some View {
        let color = Color(hex: row.project.colorHex)
        let total = max(1, row.byTag.reduce(0) { $0 + $1.duration })
        return VStack(alignment: .leading, spacing: 4) {
            Text("nach Tag")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.tertiary)
            // „ohne Tag“ immer zuletzt, auch wenn es mehr Zeit ist als einzelne Tags.
            ForEach(row.byTag.filter { $0.tag != nil } + row.byTag.filter { $0.tag == nil }, id: \.tag) { tagRow in
                let share = tagRow.duration / total
                HStack(spacing: 12) {
                    Text(tagRow.tag ?? "ohne Tag")
                        .font(.system(size: 12, weight: tagRow.tag == nil ? .regular : .medium))
                        .foregroundStyle(tagRow.tag == nil ? AnyShapeStyle(theme.tertiary) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 108, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.track)
                            Capsule()
                                .fill(tagRow.tag == nil ? AnyShapeStyle(Color.secondary.opacity(0.45)) : AnyShapeStyle(color))
                                .frame(width: max(4, geo.size.width * share))
                        }
                    }
                    .frame(width: 160, height: 6)
                    Text(ReportsFormat.duration(tagRow.duration))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(width: 40, alignment: .trailing)
                    Text(ReportsFormat.percent(share))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                    Text(tagRow.entryCount == 1 ? "1 Eintrag" : "\(tagRow.entryCount) Einträge")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiary)
                    Spacer(minLength: 0)
                }
                .monospacedDigit()
                .frame(height: 18)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Summe

    private var sumRow: some View {
        let report = data.report
        let entryCount = report.rows.reduce(0) { $0 + $1.entryCount }
        return HStack(spacing: 0) {
            Text("Summe")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 17)
            Color.clear.frame(width: Column.kind, height: 1)
            number("\(entryCount)", width: Column.count, style: .secondary)
            Text(ReportsFormat.duration(report.total))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(width: Column.duration, alignment: .trailing)
            number(ReportsFormat.duration(report.roundedTotal), width: Column.rounded, style: .secondary)
            number(ReportsFormat.duration(report.roundedBillable), width: Column.billable, style: .secondary)
            Color.clear.frame(width: Column.rate, height: 1)
            Text(data.hasAnyRate ? ReportsFormat.money(report.amount) : "–")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(data.hasAnyRate ? AnyShapeStyle(.primary) : AnyShapeStyle(theme.tertiary))
                .frame(width: Column.amount, alignment: .trailing)
        }
        .lineLimit(1)
        .padding(.vertical, 12)
    }
}
