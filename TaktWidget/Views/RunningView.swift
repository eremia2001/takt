import SwiftUI
import TaktCore
import WidgetKit

/// Zustand „läuft“.
///
/// Klein: Projekt oben, Dauer unten links, Stopp-Knopf unten rechts.
/// Mittel: dieselbe Spalte links (Stopp-Knopf direkt neben der Dauer), rechts „Weiter mit“
/// samt Schnellstarts und ganz unten die Tagessumme.
struct RunningView: View {
    let family: WidgetFamily
    let running: RunningState
    let recent: [Project]
    let duration: TimeInterval
    let todayTotal: TimeInterval

    private var project: Project { running.project }

    var body: some View {
        if family == .systemMedium {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Spacer(minLength: 0)
                    HStack(alignment: .center, spacing: 12) {
                        BigDuration(interval: duration)
                        StopButton(color: project.color)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    if !recent.isEmpty {
                        Text("Weiter mit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        QuickStartList(projects: recent)
                    }
                    Spacer(minLength: 0)
                    Text("Heute \(DurationFormat.hourMinute(todayTotal))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 4) {
                    BigDuration(interval: duration)
                    Spacer(minLength: 0)
                    StopButton(color: project.color)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    /// Farbpunkt + Projektname.
    private var header: some View {
        HStack(spacing: 6) {
            ProjectDot(color: project.color)
            Text(project.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
