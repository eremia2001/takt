import SwiftUI
import TaktCore
import WidgetKit

// MARK: - Stil „Farbfläche“
//
// Läuft: Das ganze Widget ist die Projektfarbe (sanfter Verlauf, im Dunkelmodus gedämpft),
// weiße Schrift, sehr große Dauer, weißer Stopp-Knopf.
// Pause: neutraler Grund (`.fill.tertiary`), Schnellstarts als farbig getönte Kapseln.
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

/// Klein: Projekt und Startzeit oben, unten große Dauer und Stopp-Knopf.
/// Mittel: dieselbe Spalte links, rechts „Weiter mit“ als Glas-Kapseln und die Tagessumme.
struct ColorFieldRunningView: View {
    let family: WidgetFamily
    let running: RunningState
    let recent: [Project]
    let duration: TimeInterval
    let todayTotal: TimeInterval

    private var project: Project { running.project }

    var body: some View {
        if family == .systemMedium {
            HStack(alignment: .top, spacing: 20) {
                mainColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    if !recent.isEmpty {
                        Text("Weiter mit")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.78))
                        ForEach(recent.prefix(WidgetSnapshot.maxRecent), id: \.id) { project in
                            ColorFieldGlassPill(project: project)
                        }
                    }
                    Spacer(minLength: 0)
                    Text("Heute \(DurationFormat.hourMinute(todayTotal))")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.78))
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(width: 150)
                .frame(maxHeight: .infinity)
            }
        } else {
            mainColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(project.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .truncationMode(.tail)
            Text("seit \(running.entry.startedAt, format: .dateTime.hour().minute())")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.78))
                .padding(.top, 1)
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(DurationFormat.hourMinute(duration))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                ColorFieldStopButton(color: project.color)
                    .alignmentGuide(.lastTextBaseline) { $0[.bottom] - 6 }
            }
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
        .accessibilityLabel("\(project.name) starten")
    }
}

// MARK: Pause

/// Klein: „Nichts läuft“ oben, darunter bis zu drei getönte Kapseln.
/// Mittel: links die Tagessumme groß, rechts die Kapseln.
/// Ohne Projekte nur der Hinweis, ein Projekt anzulegen.
struct ColorFieldIdleView: View {
    let family: WidgetFamily
    let recent: [Project]
    let todayTotal: TimeInterval

    var body: some View {
        if recent.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                title
                Text("Projekt in Takt anlegen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if family == .systemMedium {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    title
                    Spacer(minLength: 0)
                    // Beschriftung, damit die Tagessumme nicht als laufender Timer gelesen wird.
                    Text("Heute")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(DurationFormat.hourMinute(todayTotal))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                VStack(spacing: 6) {
                    Spacer(minLength: 0)
                    pills
                }
                .frame(width: 168)
                .frame(maxHeight: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                title
                Spacer(minLength: 8)
                pills
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var title: some View {
        Text("Nichts läuft")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var pills: some View {
        VStack(spacing: 6) {
            ForEach(recent.prefix(WidgetSnapshot.maxRecent), id: \.id) { project in
                ColorFieldTintPill(project: project)
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

// MARK: - Vorschauen

#Preview("Farbfläche klein", as: .systemSmall) {
    TaktWidget()
} timeline: {
    TaktEntry(date: .now, snapshot: .placeholder, style: .colorField)
    TaktEntry(date: .now, snapshot: .previewIdle, style: .colorField)
    TaktEntry(date: .now, snapshot: .empty, style: .colorField)
}

#Preview("Farbfläche mittel", as: .systemMedium) {
    TaktWidget()
} timeline: {
    TaktEntry(date: .now, snapshot: .placeholder, style: .colorField)
    TaktEntry(date: .now, snapshot: .previewIdle, style: .colorField)
    TaktEntry(date: .now, snapshot: .empty, style: .colorField)
}
