import AppKit
import SwiftUI
import TaktCore

/// Abschnitt „Allgemein“: Menüleiste (Stil, Schnelleingabe im Fenster, Dock-Symbol) und die
/// Kurzbefehle, die in jeder App gelten. Nach Häufigkeit geordnet; jede Einstellung mit einem Satz
/// Erklärung und – bei Kurzbefehlen – dem Standard.
/// Der Abschnitt „Timer“ (vergessener Timer) folgt im selben Reiter als `TimerSettingsSection`.
struct GeneralSettingsSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(MenuBarController.self) private var menuBar

    var body: some View {
        @Bindable var settings = settings
        @Bindable var menuBar = menuBar

        Section {
            Toggle(isOn: $settings.menuBarEnabled) {
                Text("In der Menüleiste anzeigen")
                Text("Zeigt oben rechts, was gerade läuft. Ein Klick öffnet ein kleines Fenster zum Starten und Stoppen.")
            }
            Picker(selection: $settings.menuBarStyle) {
                ForEach(MenuBarStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            } label: {
                Text("Stil")
                Text("Wie der laufende Timer oben rechts aussieht – die Vorschau zeigt „Läuft“ und „Pause“.")
            }
            .disabled(!settings.menuBarEnabled)
            MenuBarStylePreview(settings: settings)
                .disabled(!settings.menuBarEnabled)
            Toggle(isOn: $settings.menuBarShowProjectName) {
                Text("Projektname zeigen")
                Text("Nur bei den Stilen „Text“ und „Kapsel“; sonst steht dort nur die Zeit.")
            }
            .disabled(!settings.menuBarEnabled || (settings.menuBarStyle != .text && settings.menuBarStyle != .capsule))
            Toggle(isOn: $settings.menuBarShowTodayTotal) {
                Text("Tagessumme statt Laufzeit")
                Text("Zeigt, wie viel heute insgesamt erfasst ist, statt wie lange der laufende Eintrag dauert.")
            }
            .disabled(!settings.menuBarEnabled)
            Picker(selection: $settings.menuBarIdleMode) {
                ForEach(MenuBarIdleMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                Text("Wenn nichts läuft")
                Text(settings.menuBarIdleMode == .hidden
                     ? "Das Symbol erscheint erst mit einem laufenden Timer. Takt bleibt über Kurzbefehle, Widget und Dock erreichbar."
                     : "Was oben rechts zu sehen ist, solange kein Timer läuft.")
            }
            .disabled(!settings.menuBarEnabled)
            Toggle(isOn: $settings.quickEntryInMenuBar) {
                Text("Schnelleingabe im Menüleisten-Fenster")
                Text("Eingabefeld über der Projektliste, z. B. „Website 1h30“ oder „kunden 9-10:30 #meeting“.")
            }
            .disabled(!settings.menuBarEnabled)
            Toggle(isOn: $settings.hideDockIcon) {
                Text("Dock-Symbol ausblenden")
                Text(settings.menuBarEnabled
                     ? "Takt läuft dann nur in der Menüleiste – sinnvoll, wenn du das Hauptfenster selten brauchst."
                     : "Nur zusammen mit der Menüleiste möglich, sonst wäre Takt nicht mehr erreichbar.")
            }
            .disabled(!settings.menuBarEnabled)
        } header: {
            Text("Menüleiste")
        }

        Section {
            Toggle(isOn: $settings.globalShortcutEnabled) {
                Text("Timer starten/stoppen")
                Text("Stoppt den laufenden Timer oder startet das zuletzt genutzte Projekt – in jeder App, auch wenn Takt im Hintergrund ist.")
            }
            shortcutRow(
                combo: combo,
                isDefault: isDefaultShortcut,
                defaultDisplay: Self.defaultShortcutDisplay,
                isRecording: $menuBar.isRecordingShortcut,
                reset: {
                    settings.globalShortcutKeyCode = AppSettings.defaultShortcutKeyCode
                    settings.globalShortcutModifiers = AppSettings.defaultShortcutModifiers
                },
                record: { recorded in
                    settings.globalShortcutKeyCode = recorded.keyCode
                    settings.globalShortcutModifiers = recorded.modifiers.rawValue
                }
            )
            .disabled(!settings.globalShortcutEnabled)
            if let problem = menuBar.shortcutProblem, settings.globalShortcutEnabled {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            Toggle(isOn: $settings.quickEntryHotKeyEnabled) {
                Text("Schnelleingabe öffnen")
                Text("Öffnet ein schwebendes Eingabefeld über jeder App, z. B. für „Kundenportal 9-10:30“. Enter übernimmt, Esc schließt.")
            }
            shortcutRow(
                combo: quickEntryCombo,
                isDefault: isDefaultQuickEntryShortcut,
                defaultDisplay: Self.defaultQuickEntryDisplay,
                isRecording: $menuBar.isRecordingQuickEntryShortcut,
                reset: {
                    settings.quickEntryHotKeyKeyCode = AppSettings.defaultQuickEntryKeyCode
                    settings.quickEntryHotKeyModifiers = AppSettings.defaultQuickEntryModifiers
                },
                record: { recorded in
                    settings.quickEntryHotKeyKeyCode = recorded.keyCode
                    settings.quickEntryHotKeyModifiers = recorded.modifiers.rawValue
                }
            )
            .disabled(!settings.quickEntryHotKeyEnabled)
            if let problem = menuBar.quickEntryShortcutProblem, settings.quickEntryHotKeyEnabled {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Kurzbefehle überall")
        } footer: {
            Text("Zum Ändern auf die Tastenkombination klicken und die neuen Tasten drücken (mit ⌃, ⌥ oder ⌘); Esc bricht ab. Im Hauptfenster gelten zusätzlich ⌘K (Befehlspalette), ⌘N (Schnelleingabe) und ⌘. (Stoppen).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Aufnahmefeld samt „Zurücksetzen“ und Hinweis auf den Standard.
    private func shortcutRow(
        combo: KeyCombo,
        isDefault: Bool,
        defaultDisplay: String,
        isRecording: Binding<Bool>,
        reset: @escaping () -> Void,
        record: @escaping (KeyCombo) -> Void
    ) -> some View {
        LabeledContent {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !isDefault {
                    Button("Zurücksetzen", action: reset)
                        .buttonStyle(.link)
                        .font(.callout)
                        .help("Zurück auf \(defaultDisplay)")
                }
                ShortcutRecorder(combo: combo, isRecording: isRecording, onRecord: record)
                    .help("Klicken und neue Tastenkombination drücken")
            }
        } label: {
            Text("Tastenkombination")
            Text("Standard: \(defaultDisplay)")
        }
    }

    private static var defaultShortcutDisplay: String {
        KeyCombo(
            keyCode: AppSettings.defaultShortcutKeyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: AppSettings.defaultShortcutModifiers)
        ).display
    }

    private static var defaultQuickEntryDisplay: String {
        KeyCombo(
            keyCode: AppSettings.defaultQuickEntryKeyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: AppSettings.defaultQuickEntryModifiers)
        ).display
    }

    private var quickEntryCombo: KeyCombo {
        KeyCombo(
            keyCode: settings.quickEntryHotKeyKeyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: settings.quickEntryHotKeyModifiers)
        )
    }

    private var isDefaultQuickEntryShortcut: Bool {
        settings.quickEntryHotKeyKeyCode == AppSettings.defaultQuickEntryKeyCode
            && settings.quickEntryHotKeyModifiers == AppSettings.defaultQuickEntryModifiers
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

/// Live-Vorschau des Menüleisten-Stils: dasselbe Bild wie in der Menüleiste, „läuft“ und „Pause“
/// nebeneinander auf einem Streifen in der Farbe der Menüleiste (hell/dunkel wie die Einstellungen).
struct MenuBarStylePreview: View {
    let settings: AppSettings

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        HStack(spacing: 10) {
            sample(title: "Läuft", model: model(running: true, dark: dark), dark: dark)
            sample(title: "Pause", model: model(running: false, dark: dark), dark: dark)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func model(running: Bool, dark: Bool) -> MenuBarLabelModel {
        MenuBarLabelModel(
            style: settings.menuBarStyle,
            showProjectName: settings.menuBarShowProjectName,
            showTodayTotal: settings.menuBarShowTodayTotal,
            idleMode: settings.menuBarIdleMode,
            running: running
                ? MenuBarLabelModel.Running(name: "Kundenportal", colorHex: "#3A7BD5", elapsed: 84 * 60, budgetFraction: nil)
                : nil,
            todayTotal: 4 * 3600 + 10 * 60,
            isDark: dark
        )
    }

    private func sample(title: String, model: MenuBarLabelModel, dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if !model.isVisible {
                    Text("ausgeblendet")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                } else {
                    let image = MenuBarLabelRenderer.image(for: model)
                    if image.isTemplate {
                        Image(nsImage: image)
                            .renderingMode(.template)
                            .foregroundStyle(dark ? Color.white : Color.black.opacity(0.85))
                    } else {
                        Image(nsImage: image)
                    }
                }
            }
            .frame(height: 24)
            .padding(.horizontal, 10)
            .background(dark ? Color(white: 0.17) : Color(white: 0.93),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
