import AppKit
import Observation
import SwiftUI

/// Öffnet das Hilfe-Fenster (`Window(id: "help")`) mit einem Thema – von überall: App-Menü,
/// Befehlspalette, `AppNavigator.request(helpTopic:)`, Links „Mehr in der Hilfe →“ (über
/// `showHelpWindow:` im `AppDelegate`) und `takt://help/<thema>`.
///
/// SwiftUI öffnet Fenster nur über `OpenWindowAction`; die holen sich sichtbare Ansichten aus
/// ihrer Umgebung und melden sie hier an (`registerHelpWindowOpener()`).
@MainActor
@Observable
final class HelpCenter {
    static let shared = HelpCenter()

    /// Kennung der Fenster-Szene in `TaktApp`.
    static let windowID = "help"

    /// Gewähltes Thema im Hilfe-Fenster.
    var selectedTopicID = HelpContent.defaultTopicID
    /// Suchtext im Hilfe-Fenster.
    var searchText = ""

    @ObservationIgnored private var openWindowAction: OpenWindowAction?

    func register(_ openWindow: OpenWindowAction) {
        openWindowAction = openWindow
    }

    /// Fenster öffnen bzw. nach vorn holen; `topicID` wählt das Thema (Aliasse erlaubt).
    func show(topicID: String? = nil) {
        if let topicID {
            selectedTopicID = HelpContent.topic(topicID).id
            searchText = ""
        }
        NSApp.activate()
        if let openWindowAction {
            // Bei `Window`-Szenen holt `openWindow` ein schon offenes Fenster nach vorn.
            openWindowAction(id: Self.windowID)
            DispatchQueue.main.async { Self.window()?.makeKeyAndOrderFront(nil) }
        } else if let window = Self.window() {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            // Noch keine Ansicht hat sich angemeldet: über die eigene URL, `MainView` öffnet dann.
            Self.openViaURL(topicID: selectedTopicID)
        }
    }

    /// Das Hilfe-Fenster, falls es existiert (sichtbar oder minimiert).
    static func window() -> NSWindow? {
        NSApp.windows.first { window in
            window.identifier?.rawValue.hasPrefix(windowID) == true && (window.isVisible || window.isMiniaturized)
        }
    }

    private static func openViaURL(topicID: String) {
        guard let url = URL(string: "takt://help/\(topicID)") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: Bundle.main.bundleURL, configuration: configuration)
    }
}

/// Meldet die `OpenWindowAction` der Umgebung bei `HelpCenter` an.
private struct HelpWindowOpenerRegistration: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear { HelpCenter.shared.register(openWindow) }
    }
}

extension View {
    /// Damit `HelpCenter` das Hilfe-Fenster öffnen kann (in Hauptfenster und Hilfe-Fenster gesetzt).
    func registerHelpWindowOpener() -> some View {
        modifier(HelpWindowOpenerRegistration())
    }
}

/// Pfad der Projekt-Spezifikation (`docs/SPEC.md`), ermittelt aus dem Quellpfad beim Bauen.
/// Nur auf dem Entwicklungs-Mac vorhanden; sonst `nil`.
enum SpecDocument {
    static var url: URL? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Help
            .deletingLastPathComponent() // Takt
            .deletingLastPathComponent() // Projektordner
            .appendingPathComponent("docs/SPEC.md")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
