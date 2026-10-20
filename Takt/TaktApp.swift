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
    /// Menüleiste, Dock-Symbol und globaler Kurzbefehl.
    @State private var menuBarController: MenuBarController
    /// Nachfrage bei vergessenem Timer; lebt so lange wie die App.
    @State private var forgottenTimerGuard: ForgottenTimerGuard

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
        _menuBarController = State(initialValue: MenuBarController(store: store, settings: settings))
        _forgottenTimerGuard = State(initialValue: ForgottenTimerGuard(store: store, settings: settings))
    }

    var body: some Scene {
        // Kennung, damit die Menüleiste das Fenster nach dem Schließen wieder öffnen kann.
        WindowGroup(id: MenuBarController.mainWindowId) {
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
                .environment(menuBarController)
        }

        // Fenster-Stil statt Menü: eigene ruhige Oberfläche wie in der App.
        MenuBarExtra(isInserted: menuBarInserted) {
            MenuBarContent()
                .environment(store)
                .environment(settings)
                .environment(menuBarController)
        } label: {
            MenuBarLabel()
                .environment(store)
                .environment(menuBarController)
        }
        .menuBarExtraStyle(.window)
    }

    /// Schalter „In der Menüleiste anzeigen“. Entfernt der Nutzer das Symbol per ⌘-Ziehen,
    /// wird der Schalter mit ausgeschaltet.
    private var menuBarInserted: Binding<Bool> {
        Binding(
            get: { settings.menuBarEnabled },
            set: { settings.menuBarEnabled = $0 }
        )
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
