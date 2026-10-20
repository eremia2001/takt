import SwiftUI
import TaktCore

/// Abschnitt „Allgemein“ – Platzhalter. Menüleiste, Dock-Symbol und globaler Kurzbefehl
/// (Werte liegen bereits in `AppSettings`: `menuBarEnabled`, `hideDockIcon`,
/// `globalShortcutEnabled`, `globalShortcutKeyCode`, `globalShortcutModifiers`) kommen hier hinein.
struct GeneralSettingsSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Section("Allgemein") {
            // Inhalt folgt (Menüleiste, Dock, Kurzbefehl).
        }
    }
}
