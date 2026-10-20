import SwiftUI
import TaktCore
import WidgetKit

/// Das einzige Widget von Takt: laufender Timer bzw. Schnellstart.
struct TaktWidget: Widget {
    static let kind = "dev.eremiya.takt.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: Provider()) { entry in
            TaktWidgetView(entry: entry)
        }
        .configurationDisplayName("Takt")
        .description("Zeigt den laufenden Timer. Starten und Stoppen mit einem Klick.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// Wählt je nach Stil und Zustand die passende Ansicht; Hintergrund und Klickziel gelten für alle.
struct TaktWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: TaktEntry

    var body: some View {
        content
            .modifier(WidgetBackground(style: entry.style, running: entry.snapshot.running))
            .widgetURL(URL(string: "takt://today"))
    }

    @ViewBuilder
    private var content: some View {
        let snapshot = entry.snapshot
        switch (entry.style, snapshot.running) {
        case (.plain, let running?):
            RunningView(
                family: family,
                running: running,
                recent: snapshot.recent,
                duration: entry.runningDuration,
                todayTotal: entry.todayTotal
            )
        case (.plain, nil):
            IdleView(family: family, recent: snapshot.recent, todayTotal: entry.todayTotal)
        case (.colorField, let running?):
            ColorFieldRunningView(
                family: family,
                running: running,
                recent: snapshot.recent,
                duration: entry.runningDuration,
                todayTotal: entry.todayTotal
            )
        case (.colorField, nil):
            ColorFieldIdleView(family: family, recent: snapshot.recent, todayTotal: entry.todayTotal)
        case (.ring, let running?):
            RingRunningView(
                family: family,
                running: running,
                recent: snapshot.recent,
                duration: entry.runningDuration,
                todayTotal: entry.todayTotal
            )
        case (.ring, nil):
            RingIdleView(family: family, recent: snapshot.recent, todayTotal: entry.todayTotal)
        }
    }
}

/// Widget-Hintergrund: bei „Farbfläche“ mit laufendem Timer der Verlauf in Projektfarbe,
/// sonst das Systemmaterial `.fill.tertiary`.
private struct WidgetBackground: ViewModifier {
    let style: WidgetStyle
    let running: RunningState?

    func body(content: Content) -> some View {
        if style == .colorField, let running {
            content.containerBackground(for: .widget) {
                ColorFieldBackground(project: running.project)
            }
        } else {
            content.containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

// MARK: - Vorschauen

extension WidgetSnapshot {
    /// Pause mit drei Schnellstarts und bereits erfasster Zeit.
    static let previewIdle: WidgetSnapshot = {
        let projects = [placeholder.running?.project].compactMap { $0 } + placeholder.recent
        return WidgetSnapshot(running: nil, recent: projects, todayCompleted: 4 * 3600 + 10 * 60)
    }()

    /// Kein Projekt angelegt (auch Rückfall bei Lesefehlern).
    static let empty = WidgetSnapshot(running: nil, recent: [], todayCompleted: 0)
}

#Preview("Klein", as: .systemSmall) {
    TaktWidget()
} timeline: {
    TaktEntry(date: .now, snapshot: .placeholder)
    TaktEntry(date: .now, snapshot: .previewIdle)
    TaktEntry(date: .now, snapshot: .empty)
}

#Preview("Mittel", as: .systemMedium) {
    TaktWidget()
} timeline: {
    TaktEntry(date: .now, snapshot: .placeholder)
    TaktEntry(date: .now, snapshot: .previewIdle)
    TaktEntry(date: .now, snapshot: .empty)
}
