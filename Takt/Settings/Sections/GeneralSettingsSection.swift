import AppKit
import SwiftUI
import TaktCore

/// Abschnitt „Allgemein“: Menüleiste, Dock-Symbol und globaler Kurzbefehl.
/// Der Abschnitt „Timer“ (vergessener Timer) folgt im selben Reiter als `TimerSettingsSection`.
struct GeneralSettingsSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(MenuBarController.self) private var menuBar

    var body: some View {
        @Bindable var settings = settings
        @Bindable var menuBar = menuBar

        Section("Allgemein") {
            Toggle("In der Menüleiste anzeigen", isOn: $settings.menuBarEnabled)
            Toggle(isOn: $settings.hideDockIcon) {
                Text("Dock-Symbol ausblenden")
                Text(settings.menuBarEnabled
                     ? "Takt bleibt über die Menüleiste erreichbar."
                     : "Nur zusammen mit der Menüleiste möglich.")
            }
            .disabled(!settings.menuBarEnabled)
        }

        Section("Kurzbefehl") {
            Toggle(isOn: $settings.globalShortcutEnabled) {
                Text("Globaler Kurzbefehl")
                Text("Stoppt den laufenden Timer oder startet das zuletzt genutzte Projekt – auch wenn Takt im Hintergrund ist.")
            }
            LabeledContent("Tastenkombination") {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if !isDefaultShortcut {
                        Button("Zurücksetzen") {
                            settings.globalShortcutKeyCode = AppSettings.defaultShortcutKeyCode
                            settings.globalShortcutModifiers = AppSettings.defaultShortcutModifiers
                        }
                        .buttonStyle(.link)
                        .font(.callout)
                    }
                    ShortcutRecorder(combo: combo, isRecording: $menuBar.isRecordingShortcut) { recorded in
                        settings.globalShortcutKeyCode = recorded.keyCode
                        settings.globalShortcutModifiers = recorded.modifiers.rawValue
                    }
                }
            }
            .disabled(!settings.globalShortcutEnabled)
            if let problem = menuBar.shortcutProblem, settings.globalShortcutEnabled {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var combo: KeyCombo {
        KeyCombo(
            keyCode: settings.globalShortcutKeyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: settings.globalShortcutModifiers)
        )
    }

    private var isDefaultShortcut: Bool {
        settings.globalShortcutKeyCode == AppSettings.defaultShortcutKeyCode
            && settings.globalShortcutModifiers == AppSettings.defaultShortcutModifiers
    }
}
