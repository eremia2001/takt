import SwiftUI
import TaktCore

/// Abschnitt „Kalender“: Platzhalter, bis die Kalender-Anbindung (EventKit) folgt.
/// Einstellungen liegen bereits in `AppSettings` (`calendar…`), Regeln und Verknüpfungen im Store.
struct CalendarSettingsSection: View {
    var body: some View {
        Section("Kalender") {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kalender-Anbindung folgt")
                    Text("Termine in „Heute“ anzeigen, Einträge in einen Kalender spiegeln und Termine per Regel Projekten zuordnen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
