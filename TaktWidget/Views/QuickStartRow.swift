import SwiftUI
import TaktCore

/// Farbpunkt eines Projekts.
struct ProjectDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}

/// Eine Schnellstart-Zeile: Farbpunkt + Name auf dezentem Grund, Klick startet das Projekt.
struct QuickStartRow: View {
    let project: Project

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
        .accessibilityLabel("\(project.name) starten")
    }
}

/// Bis zu drei Schnellstart-Zeilen untereinander.
struct QuickStartList: View {
    let projects: [Project]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(projects.prefix(WidgetSnapshot.maxRecent), id: \.id) { project in
                QuickStartRow(project: project)
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
                Circle().fill(color)
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

/// Große Zeitangabe `h:mm` – für laufende Dauer und Tagessumme.
struct BigDuration: View {
    let interval: TimeInterval

    var body: some View {
        Text(DurationFormat.hourMinute(interval))
            .font(.system(size: 40, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}
