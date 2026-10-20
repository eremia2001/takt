import SwiftUI
import TaktCore
import WidgetKit

// MARK: - Gemeinsame Bausteine aller Stile (Widget v2)

/// Uhrzeiten im Widget, immer `HH:mm` („09:05“, „14:00“).
enum ClockFormat {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func time(_ date: Date) -> String { formatter.string(from: date) }

    /// Beginn eines geplanten Blocks; liegt er nicht mehr heute, mit „morgen“.
    static func planned(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = time(date)
        guard !calendar.isDate(date, inSameDayAs: now) else { return time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "morgen \(time)"
        }
        return time
    }
}

/// Budgetfarben: ab 80 % Orange, über 100 % Rot, sonst die Projektfarbe.
enum BudgetPalette {
    static let warning = Color(hex: "#F59E0B")
    static let over = Color(hex: "#EF4444")

    static func color(for fraction: Double, project: Color) -> Color {
        if fraction > 1 { return over }
        if fraction >= 0.8 { return warning }
        return project
    }
}

/// Überschrift im Pause-Zustand: „Nichts läuft“ bzw. im Ein-Projekt-Widget
/// „Läuft: anderes Projekt“, wenn gerade ein anderes Projekt läuft.
func idleTitle(_ entry: TaktEntry) -> String {
    entry.snapshot.fixedProjectRunningElsewhere ? "Läuft: anderes Projekt" : "Nichts läuft"
}

/// Projektname: zwei Zeilen, wo die Höhe es erlaubt (leicht verkleinerbar), sonst eine Zeile mit „…“.
struct ProjectName: View {
    let name: String
    var font: Font = .subheadline.weight(.medium)
    var twoLines = false

    var body: some View {
        Text(name)
            .font(font)
            .lineLimit(twoLines ? 2 : 1)
            .minimumScaleFactor(twoLines ? 0.85 : 1)
            .truncationMode(.tail)
    }
}

/// „Nächster Schritt“ – eine Zeile, dezent.
struct NextStepLine: View {
    let text: String
    var onColorField = false

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(onColorField ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
            .lineLimit(1)
            .truncationMode(.tail)
            .accessibilityLabel("Nächster Schritt: \(text)")
    }
}

/// „Heute h:mm“ – die Tagessumme, in allen Stilen gleich beschriftet.
struct TodayLabel: View {
    let total: TimeInterval
    var font: Font = .caption

    var body: some View {
        Text("Heute \(DurationFormat.hourMinute(total))")
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText())
            .lineLimit(1)
    }
}

/// Feiner Strich: Fortschritt bis zur Pausenerinnerung (gedeckelt bei 1 = voll).
struct BreakProgressBar: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let fraction: Double
    let tint: Color
    var onColorField = false

    var body: some View {
        let tinted = renderingMode != .fullColor
        let fill: Color = onColorField ? .white.opacity(0.75) : (tinted ? .primary.opacity(0.7) : tint.opacity(0.6))
        let track: Color = onColorField ? .white.opacity(0.22) : (tinted ? .primary.opacity(0.15) : tint.opacity(0.14))
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(fill)
                    .frame(width: max(2, proxy.size.width * min(1, max(0, fraction))))
                    .widgetAccentable()
            }
        }
        .frame(height: 2)
        .accessibilityElement()
        .accessibilityLabel("Bis zur Pause")
        .accessibilityValue("\(Int((min(1, fraction) * 100).rounded())) Prozent")
    }
}

/// Zwei kleine Farbpunkte (14 pt) im kleinen Widget: Klick wechselt zum Projekt.
struct SwitchDots: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let projects: [Project]
    var onColorField = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(projects.prefix(WidgetSnapshot.maxSwitchTargets), id: \.id) { project in
                Button(intent: StartTimerIntent(projectID: project.id.uuidString)) {
                    Circle()
                        .fill(project.color)
                        .overlay(Circle().strokeBorder(ring, lineWidth: onColorField ? 1.5 : 1))
                        .frame(width: 14, height: 14)
                        .widgetAccentable()
                        .padding(3)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Wechseln zu \(project.name)")
                .accessibilityLabel("Wechseln zu \(project.name)")
            }
        }
        .padding(.horizontal, -3)
    }

    private var ring: Color {
        if onColorField { return .white.opacity(0.9) }
        return renderingMode == .fullColor ? .primary.opacity(0.1) : .primary.opacity(0.6)
    }
}

/// Budget „12:30 / 40 h“ in `.caption2`; ab 80 % Orange, über 100 % Rot.
struct BudgetLabel: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let budget: BudgetDisplay
    var onColorField = false

    var body: some View {
        Text(budget.label)
            .font(.caption2.weight(budget.fraction >= 0.8 ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(style)
            .contentTransition(.numericText())
            .lineLimit(1)
            .accessibilityLabel("Budget \(budget.label)")
    }

    private var style: AnyShapeStyle {
        if renderingMode != .fullColor { return AnyShapeStyle(.primary) }
        if onColorField { return AnyShapeStyle(.white.opacity(0.85)) }
        if budget.fraction > 1 { return AnyShapeStyle(BudgetPalette.over) }
        if budget.fraction >= 0.8 { return AnyShapeStyle(BudgetPalette.warning) }
        return AnyShapeStyle(.secondary)
    }
}

/// Dezente Zeile im Lauf-Zustand: „Geplant 16:00 · Website“.
struct PlannedLine: View {
    let block: WidgetSnapshot.PlannedBlockInfo
    let date: Date
    var onColorField = false

    var body: some View {
        let text = block.isDue(at: date)
            ? "Geplant jetzt · \(block.project.name)"
            : "Geplant \(ClockFormat.planned(block.startAt, now: date)) · \(block.project.name)"
        HStack(spacing: 5) {
            Circle()
                .fill(block.project.color)
                .overlay(Circle().strokeBorder(onColorField ? .white.opacity(0.85) : .clear, lineWidth: 1))
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(onColorField ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
        .accessibilityElement(children: .combine)
    }
}

/// Geplanter Block im Pause-Zustand: „14:00 · Kundenportal“ mit ▶︎ (startet das Projekt).
/// Fällig: leichter Grund in Projektfarbe und „Jetzt: Kundenportal“.
/// `showsClear`: ×-Knopf daneben (nur im großen Widget).
struct PlannedBlockRow: View {
    /// Aussehen passend zum Stil: Zeile (Schlicht), Kapsel (Farbfläche), Linie (Ring).
    enum Look { case row, pill, line }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    let block: WidgetSnapshot.PlannedBlockInfo
    let date: Date
    var look: Look = .row
    var showsClear = false

    var body: some View {
        let due = block.isDue(at: date)
        HStack(spacing: 2) {
            Button(intent: StartTimerIntent(projectID: block.project.id.uuidString)) {
                HStack(spacing: look == .line ? 8 : 6) {
                    ProjectDot(color: block.project.color)
                    title(due: due)
                        .font(.subheadline.weight(due || look == .pill ? .medium : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Image(systemName: "play.fill")
                        .font(.system(size: look == .line ? 8 : 9, weight: .bold))
                        .foregroundStyle(playStyle(due: due))
                }
                .padding(.leading, look == .line && !due ? 0 : (look == .pill ? 10 : 8))
                .padding(.trailing, look == .line && !due ? 0 : (look == .pill ? 11 : 8))
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
                .background(background(due: due), in: shape)
                .contentShape(shape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                due
                    ? "Geplanter Block: \(block.project.name) jetzt starten"
                    : "Geplant um \(ClockFormat.time(block.startAt)): \(block.project.name) starten"
            )

            if showsClear {
                Button(intent: ClearPlannedBlockIntent()) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Geplanten Block entfernen")
                .accessibilityLabel("Geplanten Block entfernen")
            }
        }
    }

    private var height: CGFloat {
        switch look {
        case .row: 28
        case .pill: 30
        case .line: 27
        }
    }

    private var shape: AnyShape {
        look == .pill ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: look == .line ? 7 : 8, style: .continuous))
    }

    private func title(due: Bool) -> Text {
        if due { return Text("Jetzt: \(block.project.name)") }
        return Text(ClockFormat.planned(block.startAt, now: date)).monospacedDigit()
            + Text(" · \(block.project.name)")
    }

    private func background(due: Bool) -> AnyShapeStyle {
        if due { return AnyShapeStyle(block.project.color.opacity(scheme == .dark ? 0.24 : 0.15)) }
        return look == .line ? AnyShapeStyle(.clear) : AnyShapeStyle(.fill.quaternary)
    }

    private func playStyle(due: Bool) -> AnyShapeStyle {
        if renderingMode != .fullColor { return AnyShapeStyle(.primary) }
        return look == .line && !due ? AnyShapeStyle(.tertiary) : AnyShapeStyle(block.project.color)
    }
}

/// Schnellstart-Projekte für den Pause-Zustand: ohne das Projekt des geplanten Blocks
/// (das hat seine eigene Zeile), und eine Zeile weniger, wenn der Block angezeigt wird.
func quickStartProjects(_ entry: TaktEntry, showsPlanned: Bool) -> [Project] {
    guard showsPlanned, let block = entry.plannedBlock else {
        return Array(entry.snapshot.recent.prefix(WidgetSnapshot.maxRecent))
    }
    return Array(entry.snapshot.recent.filter { $0.id != block.project.id }.prefix(WidgetSnapshot.maxRecent - 1))
}
