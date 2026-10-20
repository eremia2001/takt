import SwiftUI
import TaktCore
import WidgetKit

// MARK: - Stil „Ring“
//
// Läuft: Dünner Ring in Projektfarbe um die Dauer. Der Ring füllt sich mit jeder laufenden
// Stunde (0…60 Min) und beginnt dann von vorn – das Widget „tickt“ minütlich sichtbar.
// Hat das Projekt ein Budget, zeigt der Ring stattdessen den Budgetverbrauch (ab 80 % Orange,
// über 100 % Rot und voll), darunter „12:30 / 40 h“.
// Pause: gepunkteter, blasser Ring, in der Mitte die Tagessumme.
// Hintergrund bleibt `.fill.tertiary` (siehe `TaktWidgetView`).

/// Ring mit Spur und Fortschritt. `progress == nil` = Pause (gepunktet, neutral).
struct HourRing: View {
    let color: Color
    let progress: Double?
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            if let progress {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(0.012, min(progress, 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            } else {
                Circle()
                    .stroke(
                        Color.secondary.opacity(0.45),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [0.1, 7])
                    )
            }
        }
        .padding(lineWidth / 2)
    }

    /// Anteil der laufenden Stunde, z. B. 1:24 → 0,4.
    static func hourProgress(_ duration: TimeInterval) -> Double {
        let minutes = Int(max(0, duration) / 60) % 60
        return Double(minutes) / 60
    }
}

/// Runder Knopf in Projektfarbe – Stopp (Quadrat) oder Start (Dreieck).
/// Die Farbe ist bei hellen Projektfarben abgedunkelt, damit die weiße Glyphe lesbar bleibt.
struct RingRoundButton: View {
    enum Kind { case stop, play }

    let project: Project
    let kind: Kind
    var size: CGFloat = 26
    var actionLabel: String? = nil

    var body: some View {
        switch kind {
        case .stop:
            Button(intent: StopTimerIntent()) { face }
                .buttonStyle(.plain)
                .accessibilityLabel(actionLabel ?? "Timer stoppen")
        case .play:
            Button(intent: StartTimerIntent(projectID: project.id.uuidString)) { face }
                .buttonStyle(.plain)
                .accessibilityLabel(actionLabel ?? "\(project.name) starten")
        }
    }

    private var face: some View {
        ZStack {
            Circle().fill(project.colorBehindWhite).widgetAccentable()
            switch kind {
            case .stop:
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(.white)
                    .frame(width: size * 0.34, height: size * 0.34)
            case .play:
                Image(systemName: "play.fill")
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: size * 0.03)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
}

/// Ring mit Mitte und Knopf unten im Ring – für Läuft und Pause gleich aufgebaut, damit der
/// Knopf in beiden Zuständen an derselben Stelle sitzt.
struct RingDial<Center: View>: View {
    let color: Color
    let progress: Double?
    let button: RingRoundButton?
    @ViewBuilder let center: Center

    var body: some View {
        ZStack {
            HourRing(color: color, progress: progress)
            center
                .offset(y: button == nil ? 0 : -((button?.size ?? 0) * 0.3))
            if let button {
                VStack {
                    Spacer(minLength: 0)
                    button
                }
                .padding(.bottom, button.size * 0.34)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: Läuft

/// Klein: Projektname, Ring mit Dauer, Pausenstrich und Stopp-Knopf, ggf. Budget, unten
/// Wechsel-Punkte und „Heute h:mm“.
/// Mittel/Karte im großen Widget: Ring links (darunter Budget und im mittleren Widget die
/// Tagessumme), rechts Projekt, nächster Schritt, „Wechseln zu“ und ggf. der geplante Block.
struct RingRunningView: View {
    let family: WidgetFamily
    let entry: TaktEntry
    let running: RunningState

    private var project: Project { running.project }
    private var showsFooter: Bool { family == .systemMedium }

    var body: some View {
        if family == .systemSmall {
            VStack(spacing: 3) {
                Text(project.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                dial(durationSize: 26, buttonSize: 22, barWidth: 36)
                if let budget = entry.budget {
                    BudgetLabel(budget: budget)
                }
                HStack(spacing: 4) {
                    SwitchDots(projects: entry.snapshot.switchTargets)
                    Spacer(minLength: 0)
                    TodayLabel(total: entry.todayTotal, font: .caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 18) {
                VStack(spacing: 3) {
                    dial(durationSize: 32, buttonSize: 26, barWidth: 48)
                    if let budget = entry.budget {
                        BudgetLabel(budget: budget)
                    }
                    if showsFooter {
                        TodayLabel(total: entry.todayTotal, font: .caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 124)

                VStack(alignment: .leading, spacing: 0) {
                    ProjectName(name: project.name, font: .subheadline.weight(.semibold), twoLines: true)
                    if let step = entry.snapshot.runningNextStep {
                        NextStepLine(text: step)
                            .padding(.top, 1)
                            .layoutPriority(1)
                    }
                    Spacer(minLength: 6)
                    if !entry.snapshot.switchTargets.isEmpty {
                        Text("Wechseln zu")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 2)
                            .layoutPriority(1)
                        RingQuickStartList(
                            projects: entry.snapshot.switchTargets,
                            limit: WidgetSnapshot.maxSwitchTargets,
                            isSwitch: true
                        )
                        .layoutPriority(1)
                    }
                    if showsFooter, let block = entry.plannedBlock {
                        PlannedLine(block: block, date: entry.date)
                            .padding(.top, 4)
                            .layoutPriority(1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }

    /// Ring: mit Budget dessen Verbrauch, sonst die laufende Stunde.
    private func dial(durationSize: CGFloat, buttonSize: CGFloat, barWidth: CGFloat) -> some View {
        let budget = entry.budget
        let color = budget.map { BudgetPalette.color(for: $0.fraction, project: project.color) } ?? project.color
        let progress = budget.map { min(1, $0.fraction) } ?? HourRing.hourProgress(entry.runningDuration)
        return RingDial(
            color: color,
            progress: progress,
            button: RingRoundButton(project: project, kind: .stop, size: buttonSize)
        ) {
            VStack(spacing: 4) {
                Text(DurationFormat.hourMinute(entry.runningDuration))
                    .font(.system(size: durationFontSize(durationSize, for: entry.runningDuration), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let fraction = entry.breakFraction {
                    BreakProgressBar(fraction: fraction, tint: project.color)
                        .frame(width: barWidth)
                }
            }
            .padding(.horizontal, 12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(budget.map { "Budget \($0.label)" } ?? "Laufende Stunde")
    }
}

// MARK: Pause

/// Klein: gepunkteter Ring mit Tagessumme und genau einem Start-Knopf an der Stelle des
/// Stopp-Knopfs – für den geplanten Block (darunter „14:00 · Website“ bzw. „Jetzt: Website“),
/// sonst für das zuletzt genutzte Projekt (darunter dessen Name).
/// Mittel/Karte im großen Widget: Ring links, rechts „Starten“ mit bis zu drei Zeilen
/// (mit geplantem Block ersetzt er die dritte; im großen Widget steht er in der Fußzeile).
/// Ohne Projekte nur der Ring mit der Tagessumme.
struct RingIdleView: View {
    @Environment(\.colorScheme) private var scheme
    let family: WidgetFamily
    let entry: TaktEntry

    private var showsPlanned: Bool { family != .systemLarge }

    var body: some View {
        let projects = quickStartProjects(entry, showsPlanned: showsPlanned)
        let block = showsPlanned ? entry.plannedBlock : nil
        if family == .systemSmall {
            small(block: block)
        } else if projects.isEmpty && block == nil {
            VStack(spacing: 6) {
                title
                dial(button: nil, compact: false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 22) {
                VStack(spacing: 6) {
                    title
                    dial(button: nil, compact: false)
                }
                .frame(width: 136)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Starten")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                    RingQuickStartList(projects: projects)
                    if let block {
                        if !projects.isEmpty {
                            Rectangle().fill(.separator).frame(height: 0.5).padding(.leading, 16)
                        }
                        PlannedBlockRow(block: block, date: entry.date, look: .line)
                    }
                    Spacer(minLength: 0)
                    if let budget = entry.budget {
                        BudgetLabel(budget: budget)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func small(block: WidgetSnapshot.PlannedBlockInfo?) -> some View {
        let target = block?.project ?? entry.snapshot.recent.first
        if let target {
            let due = block?.isDue(at: entry.date) ?? false
            let label = block.map {
                due ? "Geplanter Block: \(target.name) jetzt starten" : "Geplant um \(ClockFormat.time($0.startAt)): \(target.name) starten"
            }
            VStack(spacing: 3) {
                title
                dial(button: RingRoundButton(project: target, kind: .play, size: 24, actionLabel: label), compact: true)
                footer(target: target, block: block, due: due)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                title
                dial(button: nil, compact: false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Beschriftung des Start-Knopfs im kleinen Widget.
    @ViewBuilder
    private func footer(target: Project, block: WidgetSnapshot.PlannedBlockInfo?, due: Bool) -> some View {
        if let block {
            HStack(spacing: 4) {
                ProjectDot(color: target.color, size: 6)
                Text(due ? "Jetzt: \(target.name)" : "\(ClockFormat.planned(block.startAt, now: entry.date)) · \(target.name)")
                    .font(.caption2.weight(due ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(due ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, due ? 7 : 0)
            .padding(.vertical, due ? 2 : 0)
            .background(due ? target.color.opacity(scheme == .dark ? 0.24 : 0.15) : .clear, in: Capsule())
        } else {
            Text(target.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var title: some View {
        Text(idleTitle(entry))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func dial(button: RingRoundButton?, compact: Bool) -> some View {
        RingDial(color: .secondary, progress: nil, button: button) {
            VStack(spacing: 0) {
                Text("Heute")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(DurationFormat.hourMinute(entry.todayTotal))
                    .font(.system(size: durationFontSize(compact ? 24 : 28, for: entry.todayTotal), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .padding(.horizontal, 14)
        }
    }
}

// MARK: Schnellstart-Zeilen

/// Dezente Zeile: Farbpunkt, Name, Play-Glyphe – ohne Hintergrund, nur feine Trenner.
struct RingQuickStartRow: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let project: Project
    var actionLabel: String? = nil

    var body: some View {
        Button(intent: StartTimerIntent(projectID: project.id.uuidString)) {
            HStack(spacing: 8) {
                ProjectDot(color: project.color)
                Text(project.name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(renderingMode == .fullColor ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
            }
            .frame(height: 27)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(actionLabel ?? "\(project.name) starten")
    }
}

/// Bis zu drei Zeilen mit feinen Trennlinien.
struct RingQuickStartList: View {
    let projects: [Project]
    var limit: Int = WidgetSnapshot.maxRecent
    var isSwitch = false

    var body: some View {
        let items = Array(projects.prefix(limit))
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, project in
                RingQuickStartRow(project: project, actionLabel: isSwitch ? "Wechseln zu \(project.name)" : nil)
                if index < items.count - 1 {
                    Rectangle().fill(.separator).frame(height: 0.5).padding(.leading, 16)
                }
            }
        }
    }
}
