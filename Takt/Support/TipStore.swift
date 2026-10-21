import AppKit
import Observation
import SwiftUI

// Einmalige Kontext-Tipps und der Link „Mehr in der Hilfe →“.
//
// Ohne Store- und TaktCore-Abhängigkeit; `HelpLink` nutzt nur den (optionalen) `AppNavigator`. Die Tipp-Flags liegen nicht in `AppSettings`, sondern
// direkt in `UserDefaults` (Schlüssel `tips.dismissed`, Liste der ausgeblendeten Kennungen).

/// Ein Kontext-Tipp: dezente Zeile mit Glühbirne und ×, erscheint, bis der Nutzer sie schließt.
enum TipID: String, CaseIterable, Identifiable {
    case today
    case reports
    case projects
    case menuBar

    var id: String { rawValue }

    /// Text der Tipp-Zeile.
    var text: String {
        switch self {
        case .today: "⌘K öffnet die Befehlspalette · ⌘N springt in die Schnelleingabe"
        case .reports: "Projektzeile anklicken zeigt Einträge und Tags des Zeitraums"
        case .projects: "Rechtsklick für Bearbeiten/Archivieren · Ziehen sortiert · Doppelklick öffnet"
        case .menuBar: "Stil der Menüleiste: Einstellungen › Allgemein"
        }
    }
}

/// Merkt sich, welche Tipps ausgeblendet wurden. `@Observable`, damit alle Stellen, die denselben
/// Tipp zeigen, gleichzeitig verschwinden.
@MainActor
@Observable
final class TipStore {
    static let shared = TipStore()

    private static let key = "tips.dismissed"

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var dismissed: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dismissed = Set(defaults.stringArray(forKey: Self.key) ?? [])
    }

    func isVisible(_ tip: TipID) -> Bool { !dismissed.contains(tip.rawValue) }

    func dismiss(_ tip: TipID) {
        guard !dismissed.contains(tip.rawValue) else { return }
        dismissed.insert(tip.rawValue)
        defaults.set(dismissed.sorted(), forKey: Self.key)
    }

    /// Alle Tipps wieder zeigen (z. B. aus der Hilfe oder für Tests).
    func resetAll() {
        dismissed = []
        defaults.removeObject(forKey: Self.key)
    }
}

// MARK: - Begriffe

/// Tooltips der wiederkehrenden Begriffe – überall gleich formuliert (Heute, Berichte, Menüleiste).
enum TermHelp {
    static let nextStep = "Nächster Schritt: Notiz, die beim nächsten Start dieses Projekts angezeigt wird. Du hinterlegst sie beim Stoppen."
    static let planBlock = "Block planen: ein Wenn-dann-Plan – „Um 14:00 mache ich mit Kundenportal weiter.“ Takt erinnert zum Beginn, „Jetzt starten“ startet den Timer."
    static let switches = "Wechsel: wie oft von einem Projekt zum anderen gewechselt wurde. Weniger heißt meist fokussierter."
    static let longestBlock = "Längster Block: die längste Zeit am Stück an einem Projekt (Lücken bis 5 Min zählen mit)."
    static let billable = "Abrechenbar: Zeit von Projekten mit Schalter „Abrechenbar“, gerundet nach Einstellungen › Abrechnung › Rundung."
    static let rounded = "Gerundet: jeder Eintrag einzeln aufgerundet nach Einstellungen › Abrechnung › Rundung."
    static let effectiveRate = "Eff. Satz (effektiver Stundensatz): Betrag ÷ gesamte Business-Zeit inkl. nicht abrechenbarer Zeit. Zeigt, was eine Stunde Arbeit tatsächlich einbringt."
    static let rate = "Satz: Stundensatz des Projekts, sonst der Standard-Stundensatz (Einstellungen › Abrechnung)."
    static let weeklyGoal = "Wochenziel: abrechenbare Stunden pro Woche aus Einstellungen › Abrechnung, gekürzt um freie Tage."
    static let resume = "Weiter mit: startet das zuletzt genutzte Projekt erneut."
}

// MARK: - Hilfe

/// Absender für `showHelpWindow:` – trägt die Themen-Kennung als KVC-lesbare Eigenschaft `topic`.
/// Der Responder (AppDelegate, vom Hilfe-Agenten) liest `(sender as? NSObject)?.value(forKey: "topic")`.
final class HelpTopicSender: NSObject {
    @objc let topic: String

    init(topic: String) {
        self.topic = topic
    }
}

/// Öffnet das Hilfe-Fenster mit einem Thema. Kanonische Kennungen (Hilfe-Fenster): "start",
/// "shortcuts", "palette", "quickentry", "widget", "menubar", "music", "focus", "billing",
/// "reports", "calendar", "activity", "notifications", "permissions", "data".
///
/// Geht über die Responder-Kette (`showHelpWindow:`) statt über `AppNavigator`, damit diese Datei
/// nicht von dessen Ausbau abhängt. Antwortet niemand (z. B. im Render-Harness), passiert nichts.
enum HelpOpener {
    @MainActor
    @discardableResult
    static func open(topic: String) -> Bool {
        NSApp.sendAction(Selector(("showHelpWindow:")), to: nil, from: HelpTopicSender(topic: topic))
    }
}

/// Link „Mehr in der Hilfe →“ am Ende eines Reiters oder einer leeren Ansicht.
/// Bevorzugt `AppNavigator.request(helpTopic:)` (Navigator optional in der Umgebung); ohne Navigator
/// geht die Anfrage über die Responder-Kette (`HelpOpener`).
struct HelpLink: View {
    let topic: String
    var title = "Mehr in der Hilfe →"

    @Environment(AppNavigator.self) private var navigator: AppNavigator?

    var body: some View {
        Button(title) {
            if let navigator {
                navigator.request(helpTopic: topic)
            } else {
                HelpOpener.open(topic: topic)
            }
        }
            .buttonStyle(.link)
            .font(.callout)
            .help("Öffnet die Hilfe zu diesem Thema")
    }
}
