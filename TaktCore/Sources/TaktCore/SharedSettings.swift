import Foundation

/// Darstellung des Widgets, in der App wählbar.
public enum WidgetStyle: String, CaseIterable, Codable, Sendable {
    /// Bisheriges Design: Systemhintergrund, Projektfarbe nur als Akzent.
    case plain
    /// Im Lauf-Zustand ist das ganze Widget die Projektfarbe.
    case colorField
    /// Fortschrittsring pro laufender Stunde, Dauer in der Mitte.
    case ring

    /// Name in den Einstellungen.
    public var title: String {
        switch self {
        case .plain: "Schlicht"
        case .colorField: "Farbfläche"
        case .ring: "Ring"
        }
    }

    /// Eine Zeile Beschreibung für die Einstellungen.
    public var summary: String {
        switch self {
        case .plain: "Systemhintergrund, die Projektfarbe nur als Punkt und Knopf."
        case .colorField: "Läuft ein Timer, füllt die Projektfarbe das ganze Widget."
        case .ring: "Ein Ring füllt sich mit jeder laufenden Stunde, die Dauer steht in der Mitte."
        }
    }
}

/// Einstellungen, die App und Widget-Extension teilen – in der `UserDefaults`-Suite der App Group.
public enum SharedSettings {
    /// Schlüssel des Widget-Stils (Rohwert von `WidgetStyle`).
    public static let widgetStyleKey = "widgetStyle"

    /// Suite der App Group; ohne Zugriff darauf (fehlendes Entitlement) die Standard-Suite.
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: AppDatabase.appGroupID) ?? .standard
    }

    /// Gewählter Widget-Stil, Standard `.plain`.
    public static var widgetStyle: WidgetStyle {
        get { widgetStyle(in: defaults) }
        set { setWidgetStyle(newValue, in: defaults) }
    }

    /// Liest den Stil aus einer beliebigen Suite (für Tests injizierbar).
    /// Unbekannte oder fehlende Werte ergeben `.plain`.
    public static func widgetStyle(in defaults: UserDefaults) -> WidgetStyle {
        defaults.string(forKey: widgetStyleKey).flatMap(WidgetStyle.init(rawValue:)) ?? .plain
    }

    /// Schreibt den Stil in eine beliebige Suite.
    public static func setWidgetStyle(_ style: WidgetStyle, in defaults: UserDefaults) {
        defaults.set(style.rawValue, forKey: widgetStyleKey)
    }
}
