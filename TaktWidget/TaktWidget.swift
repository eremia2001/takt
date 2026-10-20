import SwiftUI
import TaktCore
import WidgetKit

/// Das einzige Widget von Takt: laufender Timer bzw. Schnellstart.
/// Pro Widget konfigurierbar („Widget bearbeiten“): Stil und optional ein festes Projekt.
/// `kind` bleibt unverändert, damit vorhandene Widgets weiterlaufen (mit den Standardwerten).
struct TaktWidget: Widget {
    static let kind = "dev.eremiya.takt.widget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: TaktWidgetConfigurationIntent.self, provider: Provider()) { entry in
            TaktWidgetView(entry: entry)
        }
        .configurationDisplayName("Takt")
        .description("Zeigt den laufenden Timer. Starten und Stoppen mit einem Klick. Stil und Projekt pro Widget wählbar.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// Einstieg aus WidgetKit: liest die Größe aus der Umgebung.
struct TaktWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: TaktEntry

    var body: some View {
        TaktWidgetContent(entry: entry, family: family)
    }
}

/// Inhalt samt Hintergrund und Klickziel. Die Größe wird übergeben (statt aus der Umgebung
/// gelesen), damit sich das Widget auch außerhalb von WidgetKit rendern lässt.
struct TaktWidgetContent: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    let entry: TaktEntry
    let family: WidgetFamily

    /// In der entsättigten Schreibtisch-Darstellung wird „Farbfläche“ zu „Schlicht“ –
    /// eine entfärbte Fläche wäre nur ein grauer Block.
    static func effectiveStyle(_ style: WidgetStyle, renderingMode: WidgetRenderingMode) -> WidgetStyle {
        style == .colorField && renderingMode != .fullColor ? .plain : style
    }

    /// Farbfläche als Widget-Hintergrund: nur im Lauf-Zustand, nicht im großen Widget
    /// (dort ist nur die Karte farbig).
    static func usesColorFieldBackground(_ style: WidgetStyle, running: RunningState?, family: WidgetFamily) -> Bool {
        style == .colorField && running != nil && family != .systemLarge
    }

    var body: some View {
        let style = Self.effectiveStyle(entry.style, renderingMode: renderingMode)
        Group {
            if family == .systemLarge {
                LargeView(entry: entry, style: style)
            } else {
                WidgetStateView(entry: entry, family: family, style: style)
            }
        }
        // Wechsel Pause ↔ läuft (und Projektwechsel) weich überblenden.
        .animation(.easeInOut(duration: 0.35), value: entry.running?.entry.id)
        .modifier(WidgetBackground(
            project: Self.usesColorFieldBackground(style, running: entry.running, family: family) ? entry.running?.project : nil
        ))
        .widgetURL(URL(string: "takt://today"))
    }
}

/// Wählt je nach Stil und Zustand die passende Ansicht (klein, mittel bzw. Karte im großen Widget).
struct WidgetStateView: View {
    let entry: TaktEntry
    let family: WidgetFamily
    let style: WidgetStyle

    var body: some View {
        if let running = entry.running {
            Group {
                switch style {
                case .plain: RunningView(family: family, entry: entry, running: running)
                case .colorField: ColorFieldRunningView(family: family, entry: entry, running: running)
                case .ring: RingRunningView(family: family, entry: entry, running: running)
                }
            }
            .transition(.opacity)
        } else {
            Group {
                switch style {
                case .plain: IdleView(family: family, entry: entry)
                case .colorField: ColorFieldIdleView(family: family, entry: entry)
                case .ring: RingIdleView(family: family, entry: entry)
                }
            }
            .transition(.opacity)
        }
    }
}

/// Widget-Hintergrund: mit `project` die Farbfläche (Verlauf in Projektfarbe), sonst das
/// Systemmaterial `.fill.tertiary`.
private struct WidgetBackground: ViewModifier {
    let project: Project?

    func body(content: Content) -> some View {
        if let project {
            content.containerBackground(for: .widget) {
                ColorFieldBackground(project: project)
                    .transition(.opacity)
            }
        } else {
            content.containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

// MARK: - Vorschauen

extension WidgetSnapshot {
    /// Pause mit drei Schnellstarts, geplantem Block und bereits erfasster Zeit.
    static let previewIdle: WidgetSnapshot = {
        let projects = [placeholder.running?.project].compactMap { $0 } + placeholder.recent
        return WidgetSnapshot(
            running: nil,
            recent: projects,
            todayCompleted: 4 * 3600 + 10 * 60,
            allProjects: placeholder.allProjects,
            todayEntries: placeholder.todayEntries.filter { !$0.isRunning },
            plannedBlock: placeholder.plannedBlock,
            breakReminderMinutes: placeholder.breakReminderMinutes
        )
    }()

    /// Kein Projekt angelegt (auch Rückfall bei Lesefehlern).
    static let empty = WidgetSnapshot(running: nil, recent: [], todayCompleted: 0)

    /// Dieselbe Momentaufnahme mit anderem Pomodoro-Zustand.
    func withPomodoro(_ pomodoro: PomodoroState?) -> WidgetSnapshot {
        WidgetSnapshot(
            running: running,
            recent: recent,
            todayCompleted: todayCompleted,
            switchTargets: switchTargets,
            allProjects: allProjects,
            todayEntries: todayEntries,
            runningNextStep: runningNextStep,
            plannedBlock: plannedBlock,
            breakReminderMinutes: breakReminderMinutes,
            runningBudget: runningBudget,
            fixedProjectID: fixedProjectID,
            fixedProjectRunningElsewhere: fixedProjectRunningElsewhere,
            pomodoro: pomodoro
        )
    }

    /// Pomodoro-Phase für Vorschauen: `elapsed` Minuten vorbei, `remaining` Minuten übrig.
    static func previewPomodoro(_ phase: PomodoroState.Phase, elapsed: Double, remaining: Double, cycle: Int = 2) -> PomodoroState {
        let now = Date.now
        return PomodoroState(
            enabled: true,
            phase: phase,
            phaseEndsAt: now.addingTimeInterval(remaining * 60),
            cycle: cycle,
            cyclesBeforeLongBreak: 4,
            // `updatedAt` = Beginn der Phase (so schreibt es der PomodoroController).
            updatedAt: now.addingTimeInterval(-elapsed * 60)
        )
    }

    /// Läuft, Pomodoro-Arbeit 2/4, noch 23 von 50 Minuten.
    static let previewPomodoroWork = placeholder.withPomodoro(previewPomodoro(.work, elapsed: 27, remaining: 23))
    /// Läuft (ohne automatischen Stopp) in der Pomodoro-Pause, noch 7 von 10 Minuten.
    static let previewPomodoroBreakRunning = placeholder.withPomodoro(previewPomodoro(.shortBreak, elapsed: 3, remaining: 7))
    /// Nichts läuft, Pomodoro-Pause, noch 7 von 10 Minuten.
    static let previewPomodoroBreakIdle = previewIdle.withPomodoro(previewPomodoro(.shortBreak, elapsed: 3, remaining: 7))
}

#Preview("Klein", as: .systemSmall) {
    TaktWidget()
} timeline: {
    TaktEntry(date: .now, snapshot: .placeholder)
    TaktEntry(date: .now, snapshot: .previewIdle)
    TaktEntry(date: .now, snapshot: .placeholder, style: .colorField)
    TaktEntry(date: .now, snapshot: .placeholder, style: .ring)
    TaktEntry(date: .now, snapshot: .empty)
}

#Preview("Pomodoro", as: .systemSmall) {
    TaktWidget()
} timeline: {
    TaktEntry(date: .now, snapshot: .previewPomodoroWork, style: .plain)
    TaktEntry(date: .now, snapshot: .previewPomodoroBreakRunning, style: .plain)
    TaktEntry(date: .now, snapshot: .previewPomodoroBreakIdle, style: .plain)
    TaktEntry(date: .now, snapshot: .previewPomodoroWork, style: .colorField)
    TaktEntry(date: .now, snapshot: .previewPomodoroBreakRunning, style: .colorField)
    TaktEntry(date: .now, snapshot: .previewPomodoroBreakIdle, style: .colorField)
    TaktEntry(date: .now, snapshot: .previewPomodoroWork, style: .ring)
    TaktEntry(date: .now, snapshot: .previewPomodoroBreakRunning, style: .ring)
    TaktEntry(date: .now, snapshot: .previewPomodoroBreakIdle, style: .ring)
}

#Preview("Pomodoro mittel", as: .systemMedium) {
    TaktWidget()
} timeline: {
    TaktEntry(date: .now, snapshot: .previewPomodoroWork, style: .plain)
    TaktEntry(date: .now, snapshot: .previewPomodoroBreakRunning, style: .plain)
    TaktEntry(date: .now, snapshot: .previewPomodoroBreakIdle, style: .plain)
    TaktEntry(date: .now, snapshot: .previewPomodoroWork, style: .colorField)
    TaktEntry(date: .now, snapshot: .previewPomodoroBreakRunning, style: .colorField)
    TaktEntry(date: .now, snapshot: .previewPomodoroBreakIdle, style: .colorField)
    TaktEntry(date: .now, snapshot: .previewPomodoroWork, style: .ring)
    TaktEntry(date: .now, snapshot: .previewPomodoroBreakRunning, style: .ring)
    TaktEntry(date: .now, snapshot: .previewPomodoroBreakIdle, style: .ring)
}

#Preview("Pomodoro groß", as: .systemLarge) {
    TaktWidget()
} timeline: {
    TaktEntry(date: .now, snapshot: .previewPomodoroWork, style: .plain)
    TaktEntry(date: .now, snapshot: .previewPomodoroBreakIdle, style: .plain)
    TaktEntry(date: .now, snapshot: .previewPomodoroWork, style: .colorField)
    TaktEntry(date: .now, snapshot: .previewPomodoroBreakIdle, style: .colorField)
    TaktEntry(date: .now, snapshot: .previewPomodoroWork, style: .ring)
    TaktEntry(date: .now, snapshot: .previewPomodoroBreakIdle, style: .ring)
}

#Preview("Mittel", as: .systemMedium) {
    TaktWidget()
} timeline: {
    TaktEntry(date: .now, snapshot: .placeholder)
    TaktEntry(date: .now, snapshot: .previewIdle)
    TaktEntry(date: .now, snapshot: .placeholder, style: .colorField)
    TaktEntry(date: .now, snapshot: .placeholder, style: .ring)
}

#Preview("Groß", as: .systemLarge) {
    TaktWidget()
} timeline: {
    TaktEntry(date: .now, snapshot: .placeholder)
    TaktEntry(date: .now, snapshot: .previewIdle)
    TaktEntry(date: .now, snapshot: .placeholder, style: .colorField)
    TaktEntry(date: .now, snapshot: .placeholder, style: .ring)
}
