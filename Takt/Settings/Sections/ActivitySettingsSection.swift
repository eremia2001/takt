import SwiftUI
import TaktCore

/// Abschnitt „Aktivität“: Platzhalter, bis die Aktivitäts-Erkennung folgt.
/// Einstellungen liegen bereits in `AppSettings` (`activity…`), Regeln und Proben im Store.
struct ActivitySettingsSection: View {
    var body: some View {
        Section("Aktivität") {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aktivitäts-Erkennung folgt")
                    Text("Takt erkennt an App, Fenster oder Repository, woran du arbeitest, und schlägt das passende Projekt vor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "sparkles")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
