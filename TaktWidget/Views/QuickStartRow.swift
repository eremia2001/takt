import SwiftUI
import TaktCore
import WidgetKit

/// Farbpunkt eines Projekts. In der entsättigten Schreibtisch-Darstellung (`.vibrant`/`.accented`)
/// mit feinem Ring, damit der Punkt auch ohne Farbe als Punkt lesbar bleibt.
struct ProjectDot: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        if renderingMode == .fullColor {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        } else {
            Circle()
                .fill(color)
                .overlay(Circle().strokeBorder(.primary.opacity(0.6), lineWidth: 1))
                .frame(width: size, height: size)
                .widgetAccentable()
        }
    }
}

/// Eine Schnellstart-Zeile: Farbpunkt + Name auf dezentem Grund, Klick startet das Projekt.
/// `actionLabel` überschreibt die Bedienungshilfe (z. B. „Wechseln zu …“).
struct QuickStartRow: View {
    let project: Project
    var actionLabel: String? = nil

    var body: some View {
        Button(intent: StartTimerIntent(projectID: project.id.uuidString)) {
            HStack(spacing: 6) {
                ProjectDot(color: project.color)
                Text(project.name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(actionLabel ?? "\(project.name) starten")
    }
}

/// Schnellstart-Zeilen untereinander (Standard: bis zu drei).
struct QuickStartList: View {
    let projects: [Project]
    var limit: Int = WidgetSnapshot.maxRecent
    /// Lauf-Zustand: Zeilen wechseln das Projekt (nur Bedienungshilfe-Text).
    var isSwitch = false

    var body: some View {
        VStack(spacing: 4) {
            ForEach(projects.prefix(limit), id: \.id) { project in
                QuickStartRow(project: project, actionLabel: isSwitch ? "Wechseln zu \(project.name)" : nil)
            }
        }
    }
}

/// Stopp-Knopf: Kreis in Projektfarbe mit weißem, abgerundetem Quadrat.
struct StopButton: View {
    let color: Color

    var body: some View {
        Button(intent: StopTimerIntent()) {
            ZStack {
                Circle().fill(color).widgetAccentable()
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(.white)
                    .frame(width: 10, height: 10)
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Timer stoppen")
    }
}

/// Schriftgröße für `h:mm`: ab zehn Stunden kleiner, damit „12:34“ nie zu „12:…“ wird
/// (`minimumScaleFactor` allein reicht neben dem Stopp-Knopf nicht immer).
func durationFontSize(_ base: CGFloat, for interval: TimeInterval) -> CGFloat {
    let hours = Int(max(0, interval) / 3600)
    if hours >= 100 { return base * 0.62 }
    return hours >= 10 ? base * 0.8 : base
}

/// Große Zeitangabe `h:mm` – für laufende Dauer und Tagessumme.
struct BigDuration: View {
    let interval: TimeInterval
    var size: CGFloat = 40

    var body: some View {
        Text(DurationFormat.hourMinute(interval))
            .font(.system(size: durationFontSize(size, for: interval), weight: .semibold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}
