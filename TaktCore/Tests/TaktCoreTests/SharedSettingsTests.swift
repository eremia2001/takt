import Foundation
import Testing
@testable import TaktCore

@Suite("Gemeinsame Einstellungen", .serialized)
struct SharedSettingsTests {
    /// Eigene, vor jedem Test geleerte Suite – die echte App-Group-Suite bleibt unberührt.
    private func freshDefaults() -> UserDefaults {
        let suite = "test"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Widget-Stil: Standard ist .plain, auch bei unbekanntem Wert")
    func widgetStyleDefault() {
        let defaults = freshDefaults()
        #expect(SharedSettings.widgetStyle(in: defaults) == .plain)
        defaults.set("unbekannt", forKey: SharedSettings.widgetStyleKey)
        #expect(SharedSettings.widgetStyle(in: defaults) == .plain)
    }

    @Test("Widget-Stil: Rundreise für alle Stile")
    func widgetStyleRoundTrip() {
        let defaults = freshDefaults()
        for style in WidgetStyle.allCases {
            SharedSettings.setWidgetStyle(style, in: defaults)
            #expect(defaults.string(forKey: "widgetStyle") == style.rawValue)
            #expect(SharedSettings.widgetStyle(in: defaults) == style)
        }
        defaults.removePersistentDomain(forName: "test")
    }
}
