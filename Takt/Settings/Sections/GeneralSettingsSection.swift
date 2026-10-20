import AppKit
import SwiftUI
import TaktCore

/// Abschnitt „Allgemein“: Menüleiste (samt Stil), Dock-Symbol, globaler Kurzbefehl und Schnelleingabe.
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

        Section("Menüleiste") {
            Picker("Stil", selection: $settings.menuBarStyle) {
                ForEach(MenuBarStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            MenuBarStylePreview(settings: settings)
            Toggle("Projektname zeigen", isOn: $settings.menuBarShowProjectName)
                .disabled(settings.menuBarStyle != .text && settings.menuBarStyle != .capsule)
            Toggle(isOn: $settings.menuBarShowTodayTotal) {
                Text("Tagessumme statt Laufzeit")
                Text("Zeigt, wie viel heute insgesamt erfasst ist.")
            }
            Picker(selection: $settings.menuBarIdleMode) {
                ForEach(MenuBarIdleMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                Text("Wenn nichts läuft")
                if settings.menuBarIdleMode == .hidden {
                    Text("Erscheint erst mit einem laufenden Timer. Takt bleibt über Kurzbefehle, Widget und Dock erreichbar.")
                }
            }
        }
        .disabled(!settings.menuBarEnabled)

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

        Section("Schnelleingabe") {
            Toggle(isOn: $settings.quickEntryInMenuBar) {
                Text("Im Menüleisten-Fenster")
                Text("Eingabefeld über der Projektliste, z. B. „Website 1h30“ oder „kunden 9-10:30 #meeting“.")
            }
            .disabled(!settings.menuBarEnabled)
            Toggle(isOn: $settings.quickEntryHotKeyEnabled) {
                Text("Schwebendes Fenster per Kurzbefehl")
                Text("Öffnet die Schnelleingabe über jeder App; Enter übernimmt, Esc schließt.")
            }
            LabeledContent("Tastenkombination") {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if !isDefaultQuickEntryShortcut {
                        Button("Zurücksetzen") {
                            settings.quickEntryHotKeyKeyCode = AppSettings.defaultQuickEntryKeyCode
                            settings.quickEntryHotKeyModifiers = AppSettings.defaultQuickEntryModifiers
                        }
                        .buttonStyle(.link)
                        .font(.callout)
                    }
                    ShortcutRecorder(combo: quickEntryCombo, isRecording: $menuBar.isRecordingQuickEntryShortcut) { recorded in
                        settings.quickEntryHotKeyKeyCode = recorded.keyCode
                        settings.quickEntryHotKeyModifiers = recorded.modifiers.rawValue
                    }
                }
            }
            .disabled(!settings.quickEntryHotKeyEnabled)
            if let problem = menuBar.quickEntryShortcutProblem, settings.quickEntryHotKeyEnabled {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
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
