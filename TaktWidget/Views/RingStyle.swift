import SwiftUI
import TaktCore
import WidgetKit

// MARK: - Stil „Ring“
//
// Läuft: Dünner Ring in Projektfarbe um die Dauer. Der Ring füllt sich mit jeder laufenden
// Stunde (0…60 Min) und beginnt dann von vorn – das Widget „tickt“ minütlich sichtbar.
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

    var body: some View {
        switch kind {
        case .stop:
            Button(intent: StopTimerIntent()) { face }
                .buttonStyle(.plain)
                .accessibilityLabel("Timer stoppen")
        case .play:
            Button(intent: StartTimerIntent(projectID: project.id.uuidString)) { face }
                .buttonStyle(.plain)
                .accessibilityLabel("\(project.name) starten")
        }
    }

    private var face: some View {
        ZStack {
            Circle().fill(project.colorBehindWhite)
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

/// Ring samt Überschrift, Mitte und Knopf – für Läuft und Pause gleich aufgebaut,
/// damit der Knopf in beiden Zuständen an derselben Stelle im Ring sitzt.
/// `footer` beschriftet den Knopf unterhalb des Rings (Schnellstart im kleinen Widget).
/// Mit `footer` wird der Ring kleiner; Abstände und Knopf rücken dann enger zusammen.
struct RingBlock<Center: View>: View {
    let title: String
    let titleStyle: HierarchicalShapeStyle
    let ringColor: Color
    let progress: Double?
    let button: RingRoundButton?
    var footer: String? = nil
    @ViewBuilder let center: Center

    private var compact: Bool { footer != nil }

    var body: some View {
        VStack(spacing: compact ? 3 : 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(titleStyle)
                .lineLimit(1)
                .truncationMode(.tail)
            ZStack {
                HourRing(color: ringColor, progress: progress)
                center
                    .offset(y: button == nil ? 0 : (compact ? -9 : -6))
                if let button {
                    VStack {
                        Spacer(minLength: 0)
                        button
                    }
                    .padding(.bottom, compact ? 8 : 11)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            if let footer {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

// MARK: Läuft

/// Klein: nur der Ring mit Projekt, Dauer und Stopp-Knopf.
/// Mittel: Ring links, rechts „Weiter mit“ und die Tagessumme.
struct RingRunningView: View {
    let family: WidgetFamily
    let running: RunningState
    let recent: [Project]
    let duration: TimeInterval
    let todayTotal: TimeInterval

    private var project: Project { running.project }

    var body: some View {
        if family == .systemMedium {
            HStack(spacing: 22) {
                ringBlock.frame(width: 136)
                VStack(alignment: .leading, spacing: 0) {
                    if !recent.isEmpty {
                        Text("Weiter mit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                        RingQuickStartList(projects: recent)
                    }
                    Spacer(minLength: 0)
                    Text("Heute \(DurationFormat.hourMinute(todayTotal))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else {
            ringBlock
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var ringBlock: some View {
        RingBlock(
            title: project.name,
            titleStyle: .primary,
            ringColor: project.color,
            progress: HourRing.hourProgress(duration),
            button: RingRoundButton(project: project, kind: .stop)
        ) {
            Text(DurationFormat.hourMinute(duration))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 12)
        }
    }
}

// MARK: Pause

/// Klein: gepunkteter Ring mit Tagessumme und genau einem Schnellstart (zuletzt genutztes
/// Projekt) an der Stelle des Stopp-Knopfs, darunter dessen Name.
/// Mittel: Ring links, rechts „Starten“ mit bis zu drei Zeilen.
/// Ohne Projekte nur der Ring mit der Tagessumme.
struct RingIdleView: View {
    let family: WidgetFamily
    let recent: [Project]
    let todayTotal: TimeInterval

    var body: some View {
        if recent.isEmpty {
            ringBlock(button: nil, footer: nil)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if family == .systemMedium {
            HStack(spacing: 22) {
                ringBlock(button: nil, footer: nil).frame(width: 136)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Starten")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                    RingQuickStartList(projects: recent)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else {
            let last = recent[0]
            ringBlock(button: RingRoundButton(project: last, kind: .play, size: 24), footer: last.name)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func ringBlock(button: RingRoundButton?, footer: String?) -> some View {
        RingBlock(
            title: "Nichts läuft",
            titleStyle: .secondary,
            ringColor: .secondary,
            progress: nil,
            button: button,
            footer: footer
        ) {
            VStack(spacing: 0) {
                Text("Heute")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(DurationFormat.hourMinute(todayTotal))
                    .font(.system(size: footer == nil ? 28 : 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 14)
        }
    }
}

// MARK: Schnellstart-Zeilen

/// Dezente Zeile: Farbpunkt, Name, Play-Glyphe – ohne Hintergrund, nur feine Trenner.
struct RingQuickStartRow: View {
    let project: Project

    var body: some View {
        Button(intent: StartTimerIntent(projectID: project.id.uuidString)) {
            HStack(spacing: 8) {
                Circle().fill(project.color).frame(width: 8, height: 8)
                Text(project.name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .frame(height: 27)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(project.name) starten")
    }
}

/// Bis zu drei Zeilen mit feinen Trennlinien.
struct RingQuickStartList: View {
    let projects: [Project]

    var body: some View {
        let items = Array(projects.prefix(WidgetSnapshot.maxRecent))
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, project in
                RingQuickStartRow(project: project)
                if index < items.count - 1 {
                    Rectangle().fill(.separator).frame(height: 0.5).padding(.leading, 16)
                }
            }
        }
    }
}

// MARK: - Vorschauen

#Preview("Ring klein", as: .systemSmall) {
    TaktWidget()
} timeline: {
    TaktEntry(date: .now, snapshot: .placeholder, style: .ring)
    TaktEntry(date: .now, snapshot: .previewIdle, style: .ring)
    TaktEntry(date: .now, snapshot: .empty, style: .ring)
}

#Preview("Ring mittel", as: .systemMedium) {
    TaktWidget()
} timeline: {
    TaktEntry(date: .now, snapshot: .placeholder, style: .ring)
    TaktEntry(date: .now, snapshot: .previewIdle, style: .ring)
    TaktEntry(date: .now, snapshot: .empty, style: .ring)
}
