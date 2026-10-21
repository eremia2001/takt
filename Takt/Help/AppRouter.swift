import AppKit
import SwiftUI
import TaktCore

/// Führt Ziele aus Hilfe, Einführung und App-Menü aus: Bereich zeigen, Einstellungen öffnen,
/// Befehlspalette, Schnelleingabe-Fenster, Aktionen über `AppNavigator`.
/// Holt dabei das Hauptfenster nach vorn (öffnet es, falls es geschlossen ist).
@MainActor
struct AppRouter {
    let navigator: AppNavigator
    let menuBar: MenuBarController
    let openWindow: OpenWindowAction
    let openSettings: OpenSettingsAction

    func perform(_ destination: HelpDestination) {
        switch destination {
        case .section(let section):
            navigator.request(section: section)
            showMainWindow()
        case .settings(let tab):
            navigator.request(settingsTab: tab)
            NSApp.activate()
            openSettings()
        case .commandPalette:
            togglePalette()
        case .quickEntryPanel:
            menuBar.showQuickEntry()
        case .onboarding:
            navigator.requestOnboarding()
            showMainWindow()
        case .helpTopic(let id):
            HelpCenter.shared.show(topicID: id)
        case .action(let action):
            navigator.request(action: action)
            showMainWindow()
        case .revealDatabase:
            NSWorkspace.shared.activateFileViewerSelecting([AppDatabase.defaultURL()])
        case .systemSettings(let address):
            if let url = URL(string: address) { NSWorkspace.shared.open(url) }
        }
    }

    func showMainWindow() {
        menuBar.showMainWindow(openWindow: openWindow)
    }

    /// ⌘K: Ist das Hauptfenster vorne, Palette umschalten; sonst Fenster holen und Palette öffnen.
    func togglePalette() {
        if let window = MenuBarController.mainWindow(), window.isKeyWindow {
            // Über einem Sheet (z. B. Eintrag bearbeiten) keine Palette.
            guard window.attachedSheet == nil else { return }
            navigator.togglePalette()
        } else {
            CommandPaletteRequest.post()
            showMainWindow()
        }
    }
}
