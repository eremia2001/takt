import SwiftUI
import TaktCore
import WidgetKit

// MARK: - Stil „Farbfläche“
//
// Läuft: Das ganze Widget ist die Projektfarbe (sanfter Verlauf, im Dunkelmodus gedämpft),
// weiße Schrift, sehr große Dauer, weißer Stopp-Knopf. Im großen Widget nur die Karte oben.
// Pause: neutraler Grund (`.fill.tertiary`), Schnellstarts als farbig getönte Kapseln.
// In der entsättigten Schreibtisch-Darstellung ersetzt `TaktWidgetContent` den Stil durch „Schlicht“.
//
// `ColorFieldBackground` wird in `TaktWidgetView` als `.containerBackground(for: .widget)`
// gesetzt, die Views hier sind nur der Inhalt (Standard-Padding des Containers).

/// Hintergrund im Lauf-Zustand: Verlauf in Projektfarbe.
struct ColorFieldBackground: View {
    @Environment(\.colorScheme) private var scheme
    let project: Project

    var body: some View {
        // Helle Projektfarben (Grün, Teal, Orange) dunkler ansetzen, damit Weiß lesbar bleibt.
        let base = project.colorBehindWhite
        let dark = scheme == .dark
        ZStack {
            LinearGradient(
                colors: dark
                    ? [base.mix(with: .black, by: 0.28), base.mix(with: .black, by: 0.55)]
                    : [base.mix(with: .white, by: 0.10), base.mix(with: .black, by: 0.22)],
                startPoint: .top,
                endPoint: .bottom
            )
            // Weiches Licht oben links – nimmt der Fläche das Plakative.
            RadialGradient(
                colors: [.white.opacity(dark ? 0.10 : 0.18), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 220
            )
        }
    }
}

// MARK: Läuft

/// Klein: Projekt, Startzeit (und, wenn Platz ist, „Nächster Schritt“) oben, unten große Dauer
/// mit Stopp-Knopf, Pausenstrich, Wechsel-Punkte und „Heute h:mm“.
/// Mittel/Karte im großen Widget: dieselbe Spalte links, rechts „Wechseln zu“ als Glas-Kapseln,
/// im mittleren Widget unten geplanter Block, Budget und Tagessumme.
struct ColorFieldRunningView: View {
    let family: WidgetFamily
    let entry: TaktEntry
    let running: RunningState

    private var project: Project { running.project }
    private var showsFooter: Bool { family == .systemMedium }

    var body: some View {
        if family == .systemSmall {
            ViewThatFits(in: .vertical) {
                small(showsNextStep: true)
                small(showsNextStep: false)
            }
        } else {
            HStack(alignment: .top, spacing: 20) {
                // In der Karte des großen Widgets ist es enger: „Nächster Schritt“ nur, wenn er passt.
                ViewThatFits(in: .vertical) {
                    mainColumn(durationSize: family == .systemLarge ? 38 : 48, twoLines: true, showsNextStep: true)
                    mainColumn(durationSize: family == .systemLarge ? 38 : 48, twoLines: false, showsNextStep: false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    if !entry.snapshot.switchTargets.isEmpty {
                        Text("Wechseln zu")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                        ForEach(entry.snapshot.switchTargets.prefix(WidgetSnapshot.maxSwitchTargets), id: \.id) { target in
                            ColorFieldGlassPill(project: target, actionLabel: "Wechseln zu \(target.name)")
                        }
                    }
                    Spacer(minLength: 0)
                    if showsFooter {
                        if let block = entry.plannedBlock {
                            PlannedLine(block: block, date: entry.date, onColorField: true)
                        }
                        HStack(spacing: 6) {
                            if let budget = entry.budget { BudgetLabel(budget: budget, onColorField: true) }
                            Spacer(minLength: 0)
                            TodayLabel(total: entry.todayTotal, font: .caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .frame(width: family == .systemLarge ? 140 : 150)
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func small(showsNextStep: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            mainColumn(durationSize: 44, twoLines: false, showsNextStep: showsNextStep)
            HStack(spacing: 6) {
                SwitchDots(projects: entry.snapshot.switchTargets, onColorField: true)
                Spacer(minLength: 0)
                TodayLabel(total: entry.todayTotal, font: .caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(height: 20)
            .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func mainColumn(durationSize: CGFloat, twoLines: Bool, showsNextStep: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ProjectName(name: project.name, font: .subheadline.weight(.semibold), twoLines: twoLines)
                .foregroundStyle(.white.opacity(0.95))
            Text("seit \(ClockFormat.time(running.entry.startedAt))")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.8))
                .padding(.top, 1)
                .layoutPriority(1)
            if showsNextStep, let step = entry.snapshot.runningNextStep {
                NextStepLine(text: step, onColorField: true)
                    .padding(.top, 1)
                    .layoutPriority(1)
            }
            Spacer(minLength: 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(DurationFormat.hourMinute(entry.runningDuration))
                        .font(.system(size: durationFontSize(durationSize, for: entry.runningDuration), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    ColorFieldStopButton(color: project.color)
                        .alignmentGuide(.lastTextBaseline) { $0[.bottom] - 6 }
                }
                RunningProgressLine(entry: entry, tint: project.color, onColorField: true, compact: family == .systemSmall)
            }
            .layoutPriority(2)
        }
    }
}

/// Weißer Kreis mit Quadrat in Projektfarbe – hebt sich von der Farbfläche ab.
struct ColorFieldStopButton: View {
    let color: Color

    var body: some View {
        Button(intent: StopTimerIntent()) {
            ZStack {
                Circle().fill(.white)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color)
                    .frame(width: 12, height: 12)
            }
            .frame(width: 34, height: 34)
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Timer stoppen")
    }
}

/// Schnellstart auf der Farbfläche: Glas-Kapsel, Farbpunkt mit weißem Rand.
struct ColorFieldGlassPill: View {
    let project: Project
    var actionLabel: String? = nil

    var body: some View {
        Button(intent: StartTimerIntent(projectID: project.id.uuidString)) {
            HStack(spacing: 7) {
                Circle()
                    .fill(project.color)
                    .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1))
                    .frame(width: 8, height: 8)
                Text(project.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.white.opacity(0.16), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(actionLabel ?? "\(project.name) starten")
    }
}

// MARK: Pause

/// Klein: „Nichts läuft“ und „Heute h:mm“ oben, darunter bis zu drei getönte Kapseln
/// (mit geplantem Block ersetzt er die dritte).
/// Mittel/Karte im großen Widget: links die Tagessumme groß, rechts die Kapseln.
/// Ohne Projekte nur der Hinweis, ein Projekt anzulegen.
struct ColorFieldIdleView: View {
    let family: WidgetFamily
    let entry: TaktEntry

    private var showsPlanned: Bool { family != .systemLarge }

    var body: some View {
        let projects = quickStartProjects(entry, showsPlanned: showsPlanned)
        let block = showsPlanned ? entry.plannedBlock : nil
        let pomodoro = entry.pomodoroBreak
        if projects.isEmpty && block == nil {
            EmptyStateView(entry: entry)
        } else if family == .systemSmall {
            VStack(alignment: .leading, spacing: 0) {
                title
                if let pomodoro {
                    PomodoroBreakLine(pomodoro: pomodoro, font: .caption.weight(.medium))
                        .padding(.top, 1)
                }
                TodayLabel(total: entry.todayTotal, font: .caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                Spacer(minLength: 6)
                // Mit Pausenzeile reicht die Höhe nur für zwei Kapseln.
                pills(pomodoro == nil ? projects : quickStartProjects(projects, block: block, maxRows: 2), block: block)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    title
                    if let pomodoro {
                        PomodoroBreakLine(pomodoro: pomodoro, font: .caption.weight(.medium)).padding(.top, 2)
                    }
                    if let budget = entry.budget {
                        BudgetLabel(budget: budget).padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                    // Beschriftung, damit die Tagessumme nicht als laufender Timer gelesen wird.
                    Text("Heute")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(DurationFormat.hourMinute(entry.todayTotal))
                        .font(.system(size: durationFontSize(48, for: entry.todayTotal), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                VStack(spacing: 6) {
                    Spacer(minLength: 0)
                    pills(projects, block: block)
                }
                .frame(width: 168)
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var title: some View {
        Text(idleTitle(entry))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    private func pills(_ projects: [Project], block: WidgetSnapshot.PlannedBlockInfo?) -> some View {
        VStack(spacing: 6) {
            ForEach(projects, id: \.id) { project in
                ColorFieldTintPill(project: project)
            }
            if let block {
                PlannedBlockRow(block: block, date: entry.date, look: .pill)
            }
        }
    }
}

/// Schnellstart auf neutralem Grund: Kapsel mit 15 % Projektfarbe, Farbpunkt, Play-Glyphe.
struct ColorFieldTintPill: View {
    @Environment(\.colorScheme) private var scheme
    let project: Project

    var body: some View {
        Button(intent: StartTimerIntent(projectID: project.id.uuidString)) {
            HStack(spacing: 7) {
                Circle().fill(project.color).frame(width: 8, height: 8)
                Text(project.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(project.color)
            }
            .padding(.leading, 10)
            .padding(.trailing, 11)
            .frame(height: 30)
            .background(project.color.opacity(scheme == .dark ? 0.24 : 0.15), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(project.name) starten")
    }
}
