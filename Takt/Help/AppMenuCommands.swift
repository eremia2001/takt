import AppKit
import SwiftUI
import TaktCore

/// Menüleiste der App (Takt · Ablage · Bearbeiten · Darstellung · Timer · Fenster · Hilfe):
/// Jede Funktion mit Kürzel steht hier, damit man sie findet und sich das Kürzel einprägt.
///
/// Kürzel, die eine Ansicht selbst hat (⌘1–3 Tabs, ⌘N Feld in „Heute“, ⌘. Stopp-Popover), behält
/// die Ansicht: AppKit fragt bei Tastenäquivalenten erst das Fenster, dann das Menü. Das Menü greift
/// also nur, wo die Ansicht nicht sichtbar ist, und führt dann dieselbe Sache über den Navigator aus.
/// Solange die Befehlspalette offen ist, sind diese Menüeinträge aus (⌘1–9 gehören der Palette).
/// Globale Kurzbefehle (⌃⌥⌘T, ⌃⌥⌘N) fängt das System vorher ab – im Menü stehen sie nur zur Anzeige.
struct AppMenuCommands: Commands {
    let store: TaktStore
    let settings: AppSettings
    let navigator: AppNavigator
    let menuBar: MenuBarController

    var body: some Commands {
        // Takt: Freigaben neben den Einstellungen.
        CommandGroup(after: .appSettings) {
            Button("Freigaben …") { HelpCenter.shared.show(topicID: "permissions") }
        }

        // Ablage
        CommandGroup(replacing: .newItem) {
            MenuItems(context: context) { router in
                Button("Neuer Eintrag …") { router.perform(.action(.newEntry)) }
                Button("Neues Projekt …") { router.perform(.action(.newProject)) }
            }
        }
        CommandGroup(replacing: .importExport) {
            MenuItems(context: context) { router in
                Button("Einträge als CSV exportieren …") { router.perform(.action(.exportEntriesCSV)) }
                Button("Zusammenfassung als CSV exportieren …") { router.perform(.action(.exportSummaryCSV)) }
                Button("Timesheet als PDF …") { router.perform(.action(.exportTimesheetPDF)) }
                Divider()
                Button("Toggl importieren …") { router.perform(.action(.importToggl)) }
            }
        }

        // Darstellung
        CommandGroup(before: .toolbar) {
            ViewMenuItems(context: context)
            Divider()
        }

        // Timer
        CommandMenu("Timer") {
            TimerMenuItems(context: context)
        }

        // Hilfe
        CommandGroup(replacing: .help) {
            MenuItems(context: context) { router in
                Button("Takt-Hilfe") { HelpCenter.shared.show() }
                    .keyboardShortcut("?", modifiers: .command)
                Button("Tastaturkürzel …") { HelpCenter.shared.show(topicID: "shortcuts") }
                Button("Freigaben prüfen …") { HelpCenter.shared.show(topicID: "permissions") }
                Button("Einführung erneut zeigen …") { router.perform(.onboarding) }
                if let spec = SpecDocument.url {
                    Divider()
                    Button("Spezifikation öffnen") { NSWorkspace.shared.open(spec) }
                }
            }
        }
    }

    private var context: MenuContext {
        MenuContext(store: store, settings: settings, navigator: navigator, menuBar: menuBar)
    }
}

/// Abhängigkeiten der Menüeinträge.
struct MenuContext {
    let store: TaktStore
    let settings: AppSettings
    let navigator: AppNavigator
    let menuBar: MenuBarController
}

/// Menüinhalt als View: liest `openWindow`/`openSettings` aus der Umgebung, meldet das Öffnen des
/// Hilfe-Fensters an und beobachtet Store/Navigator zuverlässig (dynamische Titel, aus/an).
private struct MenuItems<Content: View>: View {
    let context: MenuContext
    @ViewBuilder let content: (AppRouter) -> Content

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        content(AppRouter(navigator: context.navigator, menuBar: context.menuBar,
                          openWindow: openWindow, openSettings: openSettings))
            .onAppear { HelpCenter.shared.register(openWindow) }
    }
}

private struct ViewMenuItems: View {
    let context: MenuContext

    var body: some View {
        MenuItems(context: context) { router in
            let paletteOpen = context.navigator.isPaletteShown
            ForEach(AppSection.allCases) { section in
                Button(section.title) { router.perform(.section(section)) }
                    .keyboardShortcut(section.shortcut, modifiers: .command)
                    .disabled(paletteOpen)
            }
            Divider()
            ForEach(Array(ReportPeriodKind.menuKinds.enumerated()), id: \.offset) { index, kind in
                Button("Bericht: \(kind.title)") {
                    context.navigator.request(reportKind: kind)
                    router.showMainWindow()
                }
                // ⌥⌘ statt ⇧⌘: Auf deutscher Tastatur wird ⇧1 zu „!“ und das Menü erkennt ⇧⌘1 nicht.
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .option])
                .disabled(paletteOpen)
            }
        }
    }
}

private extension ReportPeriodKind {
    /// Tag, Woche, Monat, Jahr (ohne frei gewählten Zeitraum).
    static var menuKinds: [ReportPeriodKind] { [.day, .week, .month, .year] }
}

private struct TimerMenuItems: View {
    let context: MenuContext

    var body: some View {
        MenuItems(context: context) { router in
            let store = context.store
            let settings = context.settings
            let paletteOpen = context.navigator.isPaletteShown
            let runningId = store.running?.project.id

            Menu("Starten") {
                if store.projects.isEmpty {
                    Button("Noch keine Projekte – Projekt anlegen …") { router.perform(.action(.newProject)) }
                }
                ForEach(store.projects) { project in
                    Button {
                        context.menuBar.start(project.id)
                    } label: {
                        Text(project.id == runningId ? "\(project.name) (läuft)" : project.name)
                    }
                    .disabled(project.id == runningId)
                }
            }

            Button(store.running.map { "Stoppen (\($0.project.name))" } ?? "Stoppen") {
                // Wie der Kurzbefehl: stoppen ohne Notiz, mit kurzer Einblendung.
                if store.running != nil { context.menuBar.toggleTimerFromShortcut() }
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(store.running == nil || paletteOpen)

            let toggle = Self.combo(keyCode: settings.globalShortcutKeyCode, modifiers: settings.globalShortcutModifiers)
            Button(Self.title(resumeTitle(store), combo: toggle, enabled: settings.globalShortcutEnabled)) {
                context.menuBar.toggleTimerFromShortcut()
            }
            .keyboardShortcut(settings.globalShortcutEnabled ? toggle.shortcut : nil)
            .disabled(store.running != nil || (store.lastUsedProject ?? store.projects.first) == nil)

            Divider()

            Button("Schnelleingabe") { context.menuBar.showQuickEntry() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(paletteOpen)

            let quick = Self.combo(keyCode: settings.quickEntryHotKeyKeyCode, modifiers: settings.quickEntryHotKeyModifiers)
            Button(Self.title("Schnelleingabe-Fenster", combo: quick, enabled: settings.quickEntryHotKeyEnabled)) {
                context.menuBar.showQuickEntry()
            }
            .keyboardShortcut(settings.quickEntryHotKeyEnabled ? quick.shortcut : nil)

            Button("Block planen …") { router.perform(.action(.planBlock)) }

            Divider()

            Button("Befehle …") { router.togglePalette() }
                .keyboardShortcut("k", modifiers: .command)
        }
    }

    private func resumeTitle(_ store: TaktStore) -> String {
        if let project = store.lastUsedProject ?? store.projects.first {
            return "Weiter mit \(project.name)"
        }
        return "Weiter mit letztem Projekt"
    }

    /// Globale Kombination als Menü-Kürzel, wenn die Taste ein einfaches Zeichen ist; sonst steht
    /// sie im Titel („… (⌃⌥⌘F5)“).
    struct Combo {
        let display: String
        let shortcut: KeyboardShortcut?
    }

    static func combo(keyCode: Int, modifiers raw: UInt) -> Combo {
        let combo = KeyCombo(keyCode: keyCode, modifiers: NSEvent.ModifierFlags(rawValue: raw))
        let name = KeyCombo.keyName(keyCode)
        var shortcut: KeyboardShortcut?
        if name.count == 1, let character = name.lowercased().first, character.isLetter || character.isNumber {
            var modifiers: EventModifiers = []
            if combo.modifiers.contains(.control) { modifiers.insert(.control) }
            if combo.modifiers.contains(.option) { modifiers.insert(.option) }
            if combo.modifiers.contains(.shift) { modifiers.insert(.shift) }
            if combo.modifiers.contains(.command) { modifiers.insert(.command) }
            shortcut = KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
        }
        return Combo(display: combo.display, shortcut: shortcut)
    }

    static func title(_ base: String, combo: Combo, enabled: Bool) -> String {
        guard enabled else { return base }
        return combo.shortcut == nil ? "\(base) (\(combo.display))" : base
    }
}
