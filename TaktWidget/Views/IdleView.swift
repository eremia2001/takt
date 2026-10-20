import SwiftUI
import TaktCore
import WidgetKit

/// Zustand „Pause“.
///
/// Klein: „Nichts läuft“ oben, darunter bis zu drei Schnellstarts.
/// Mittel: links „Nichts läuft“ und groß die Tagessumme, rechts die Schnellstarts.
/// Ohne Projekte in beiden Größen nur der Hinweis, ein Projekt anzulegen.
struct IdleView: View {
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
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    title
                    Spacer(minLength: 0)
                    // Beschriftung, damit die Tagessumme nicht als laufender Timer gelesen wird.
                    Text("Heute")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    BigDuration(interval: todayTotal)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    QuickStartList(projects: recent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                title
                Spacer(minLength: 8)
                QuickStartList(projects: recent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var title: some View {
        Text("Nichts läuft")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}
