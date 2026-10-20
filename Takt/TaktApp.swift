import AppKit
import SwiftUI
import TaktCore

@main
struct TaktApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var store: TaktStore
    @State private var settings: AppSettings
    @State private var musicController: MusicController
    @State private var breakReminder: BreakReminder

    init() {
        let settings = AppSettings()
        let musicController = MusicController(settings: settings)
        let breakReminder = BreakReminder(settings: settings, musicController: musicController)
        let store = TaktStore()
        // Ab hier meldet der Store Timer-Übergänge an Musik und Pausenerinnerung.
        store.attach(musicController: musicController, breakReminder: breakReminder)

        _settings = State(initialValue: settings)
        _musicController = State(initialValue: musicController)
        _breakReminder = State(initialValue: breakReminder)
        _store = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(store)
                .environment(settings)
                .environment(musicController)
                .environment(breakReminder)
                // Eingehende URLs (z. B. `takt://today` vom Widget) im vorhandenen Fenster
                // behandeln statt ein neues zu öffnen.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        // Keine sichtbare Titelleiste: Der eigene Fensterkopf liegt neben den Ampeln.
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 920, height: 600)
        // Mindestgröße kommt aus dem Inhalt (760 × 520).
        .windowResizability(.contentMinSize)
        .commands {
            // Takt hat genau ein Hauptfenster; „Neues Fenster“ entfällt.
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environment(store)
                .environment(settings)
                .environment(musicController)
                .environment(breakReminder)
        }
    }
}

/// Hält die App nach dem Schließen des Fensters am Leben, damit sie weiter auf Starts und
/// Stopps aus dem Widget reagiert (Musik, Pausenerinnerung).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Klick aufs Dock-Symbol ohne sichtbares Fenster: ein minimiertes Fenster zurückholen,
    /// sonst öffnet SwiftUI (Rückgabe `true`) das Hauptfenster neu.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        if let window = sender.windows.first(where: { $0.isMiniaturized && $0.canBecomeMain }) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            return false
        }
        return true
    }
}
