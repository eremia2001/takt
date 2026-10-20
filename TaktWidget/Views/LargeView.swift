import SwiftUI
import TaktCore
import WidgetKit

// MARK: - Großes Widget
//
// Oben die Karte wie im mittleren Widget (stilabhängig; „Farbfläche“ läuft als farbige Karte),
// darunter die Tagesleiste, darunter alle Projekte als Schnellstarts in zwei Spalten,
// unten geplanter Block (mit ×) und „Heute h:mm“.
// Ein-Projekt-Widget: Tagesleiste nur mit dessen Einträgen, die Projektliste entfällt.

struct LargeView: View {
    let entry: TaktEntry
    /// Tatsächlicher Stil (in der entsättigten Darstellung nie „Farbfläche“).
    let style: WidgetStyle

    static let cardHeight: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            card
                .frame(height: Self.cardHeight)
            // Ohne Projekte und Einträge gibt es nichts einzuordnen.
            if !entry.snapshot.allProjects.isEmpty || !entry.dayEntries.isEmpty {
                DayBar(entries: entry.dayEntries, date: entry.date)
                    .padding(.top, 2)
            }
            if !entry.isFixed && !entry.snapshot.allProjects.isEmpty {
                // Ohne Fußzeile ist Platz für eine vierte Zeile.
                ProjectGrid(entry: entry, maxItems: hasFooter ? 6 : 8)
            }
            Spacer(minLength: 0)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var hasFooter: Bool { entry.plannedBlock != nil || entry.running != nil }

    @ViewBuilder
    private var card: some View {
        if style == .colorField, let running = entry.running {
            ColorFieldRunningView(family: .systemLarge, entry: entry, running: running)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background {
                    ColorFieldBackground(project: running.project)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .transition(.opacity)
        } else {
            WidgetStateView(entry: entry, family: .systemLarge, style: style)
        }
    }

    /// Fußzeile: geplanter Block (Pause: Zeile mit ▶︎ und ×, läuft: dezente Zeile mit ×) und,
    /// solange ein Timer läuft, Budget und „Heute h:mm“ – in Pause steht die Tagessumme groß
    /// in der Karte.
    @ViewBuilder
    private var footer: some View {
        let block = entry.plannedBlock
        if hasFooter {
            HStack(spacing: 10) {
                if let block {
                    if entry.running != nil {
                        HStack(spacing: 2) {
                            PlannedLine(block: block, date: entry.date)
                            ClearPlannedBlockButton()
                        }
                    } else {
                        PlannedBlockRow(block: block, date: entry.date, look: rowLook, showsClear: true)
                            .frame(maxWidth: 240)
                    }
                }
                Spacer(minLength: 0)
                if entry.running != nil {
                    // Im Ring-Stil steht das Budget schon unter dem Ring.
                    if style != .ring, let budget = entry.budget {
                        BudgetLabel(budget: budget)
                    }
                    TodayLabel(total: entry.todayTotal, font: .caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 24)
        }
    }

    private var rowLook: PlannedBlockRow.Look {
        switch style {
        case .plain: .row
        case .colorField: .pill
        case .ring: .line
        }
    }
}

/// Kleiner ×-Knopf: geplanten Block entfernen.
struct ClearPlannedBlockButton: View {
    var body: some View {
        Button(intent: ClearPlannedBlockIntent()) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Geplanten Block entfernen")
        .accessibilityLabel("Geplanten Block entfernen")
    }
}

// MARK: - Tagesleiste

/// Heutige Einträge als farbige Abschnitte auf einer Zeitachse 8–19 Uhr (erweitert, wenn
/// Einträge davor oder danach liegen), dazu eine Jetzt-Marke und Stundenmarken.
struct DayBar: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entries: [WidgetSnapshot.TodayEntry]
    let date: Date
    var calendar: Calendar = .current

    static let defaultStartHour = 8
    static let defaultEndHour = 19

    private struct Axis {
        let start: Date
        let span: TimeInterval
        let startHour: Int
        let endHour: Int

        func fraction(_ time: Date) -> CGFloat {
            CGFloat(min(1, max(0, time.timeIntervalSince(start) / span)))
        }

        func contains(_ time: Date) -> Bool {
            time >= start && time <= start.addingTimeInterval(span)
        }
    }

    private var axis: Axis {
        let day = calendar.startOfDay(for: date)
        var startHour = Self.defaultStartHour
        var endHour = Self.defaultEndHour
        for entry in entries {
            let from = entry.startedAt.timeIntervalSince(day) / 3600
            let to = (entry.endedAt ?? date).timeIntervalSince(day) / 3600
            startHour = min(startHour, Int(floor(from)))
            endHour = max(endHour, Int(ceil(to)))
        }
        startHour = max(0, startHour)
        endHour = min(24, max(endHour, startHour + 1))
        return Axis(
            start: day.addingTimeInterval(Double(startHour) * 3600),
            span: Double(endHour - startHour) * 3600,
            startHour: startHour,
            endHour: endHour
        )
    }

    var body: some View {
        let axis = axis
        VStack(spacing: 3) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.primary.opacity(0.07))
                        ForEach(entries.indices, id: \.self) { index in
                            let entry = entries[index]
                            let from = axis.fraction(entry.startedAt) * width
                            let to = axis.fraction(entry.endedAt ?? date) * width
                            Rectangle()
                                .fill(Color(hex: entry.colorHex))
                                .frame(width: max(1.5, to - from))
                                .offset(x: from)
                                .widgetAccentable()
                        }
                    }
                    .frame(height: 10)
                    .clipShape(Capsule())

                    if axis.contains(date) {
                        Capsule()
                            .fill(.primary)
                            .frame(width: 2, height: 16)
                            .offset(x: min(width - 2, max(0, axis.fraction(date) * width - 1)))
                    }
                }
                .frame(width: width, height: proxy.size.height)
            }
            .frame(height: 16)

            GeometryReader { proxy in
                let width = proxy.size.width
                ForEach(hourLabels(axis), id: \.self) { hour in
                    let x = CGFloat(hour - axis.startHour) / CGFloat(axis.endHour - axis.startHour) * width
                    Text("\(hour)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(renderingMode == .fullColor ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                        .fixedSize()
                        .position(x: min(width - 6, max(6, x)), y: proxy.size.height / 2)
                }
            }
            .frame(height: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tagesleiste \(axis.startHour) bis \(axis.endHour) Uhr")
    }

    /// Stundenmarken im Abstand von 2, 3 oder 4 Stunden (je nach Spanne), auf vollen Vielfachen.
    private func hourLabels(_ axis: Axis) -> [Int] {
        let range = axis.endHour - axis.startHour
        let step = range <= 12 ? 2 : (range <= 18 ? 3 : 4)
        let first = Int((Double(axis.startHour) / Double(step)).rounded(.up)) * step
        return Array(stride(from: first, through: axis.endHour, by: step))
    }
}

// MARK: - Projektliste

/// Alle aktiven Projekte in zwei Spalten: Farbpunkt, Name, heutige Zeit; das laufende ist
/// farbig hinterlegt. Höchstens `maxItems` Felder – bei mehr Projekten zeigt das letzte „+N weitere“.
struct ProjectGrid: View {
    let entry: TaktEntry
    var maxItems = 8

    static let rowHeight: CGFloat = 24

    var body: some View {
        let projects = entry.snapshot.allProjects
        let overflow = projects.count > maxItems
        let shown = overflow ? Array(projects.prefix(maxItems - 1)) : projects
        let count = shown.count + (overflow ? 1 : 0)
        Grid(horizontalSpacing: 8, verticalSpacing: 4) {
            ForEach(Array(stride(from: 0, to: count, by: 2)), id: \.self) { row in
                GridRow {
                    cell(row, shown: shown, total: projects.count)
                    cell(row + 1, shown: shown, total: projects.count)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ index: Int, shown: [Project], total: Int) -> some View {
        if index < shown.count {
            ProjectCell(
                project: shown[index],
                isRunning: entry.running?.project.id == shown[index].id,
                todayTime: entry.todayTime(for: shown[index].id)
            )
        } else if index == shown.count && total > shown.count {
            Text("+\(total - shown.count) weitere")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: ProjectGrid.rowHeight, maxHeight: ProjectGrid.rowHeight, alignment: .leading)
                .padding(.leading, 8)
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: ProjectGrid.rowHeight, maxHeight: ProjectGrid.rowHeight)
        }
    }
}

/// Ein Projekt im großen Widget; Klick startet es (das laufende bleibt laufen).
struct ProjectCell: View {
    @Environment(\.colorScheme) private var scheme
    let project: Project
    let isRunning: Bool
    let todayTime: TimeInterval

    var body: some View {
        let time = DurationFormat.hourMinute(todayTime)
        Button(intent: StartTimerIntent(projectID: project.id.uuidString)) {
            HStack(spacing: 6) {
                ProjectDot(color: project.color)
                Text(project.name)
                    .font(.subheadline.weight(isRunning ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if todayTime >= 60 {
                    Text(time)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(isRunning ? .primary : .secondary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: ProjectGrid.rowHeight, maxHeight: ProjectGrid.rowHeight, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRunning ? "\(project.name) läuft, heute \(time)" : "\(project.name) starten, heute \(time)")
    }

    private var background: AnyShapeStyle {
        isRunning
            ? AnyShapeStyle(project.color.opacity(scheme == .dark ? 0.26 : 0.16))
            : AnyShapeStyle(.fill.quaternary)
    }
}
