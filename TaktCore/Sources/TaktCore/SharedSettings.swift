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
/// Die App schreibt (`AppSettings` spiegelt seine Werte hierher), das Widget liest nur.
public enum SharedSettings {
    /// Schlüssel des Widget-Stils (Rohwert von `WidgetStyle`).
    public static let widgetStyleKey = "widgetStyle"
    /// Schlüssel der Pausenerinnerung (Spiegel von `AppSettings`).
    public static let breakReminderEnabledKey = "breakReminderEnabled"
    public static let breakReminderMinutesKey = "breakReminderMinutes"

    /// Standarddauer bis zur Pausenerinnerung in Minuten.
    public static let defaultBreakReminderMinutes = 75

    /// Suite der App Group; ohne Zugriff darauf (fehlendes Entitlement) die Standard-Suite.
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: AppDatabase.appGroupID) ?? .standard
    }

    // MARK: Widget-Stil

    /// Standardstil für neu hinzugefügte Widgets (einzelne Widgets können abweichen),
    /// Standard `.plain`.
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

    // MARK: Pausenerinnerung

    /// Pausenerinnerung eingeschaltet; Standard `true` (wie in der App).
    public static var breakReminderEnabled: Bool {
        get { breakReminderEnabled(in: defaults) }
        set { setBreakReminderEnabled(newValue, in: defaults) }
    }

    /// Minuten nach Timer-Start bis zur Erinnerung; Standard 75.
    public static var breakReminderMinutes: Int {
        get { breakReminderMinutes(in: defaults) }
        set { setBreakReminderMinutes(newValue, in: defaults) }
    }

    public static func breakReminderEnabled(in defaults: UserDefaults) -> Bool {
        (defaults.object(forKey: breakReminderEnabledKey) as? Bool) ?? true
    }

    public static func setBreakReminderEnabled(_ enabled: Bool, in defaults: UserDefaults) {
        defaults.set(enabled, forKey: breakReminderEnabledKey)
    }

    /// Fehlende oder unsinnige Werte (≤ 0) ergeben 75.
    public static func breakReminderMinutes(in defaults: UserDefaults) -> Int {
        let value = defaults.integer(forKey: breakReminderMinutesKey)
        return value > 0 ? value : defaultBreakReminderMinutes
    }

    public static func setBreakReminderMinutes(_ minutes: Int, in defaults: UserDefaults) {
        defaults.set(minutes, forKey: breakReminderMinutesKey)
    }

    /// Minuten bis zur Pausenerinnerung, `nil` wenn sie ausgeschaltet ist (für `WidgetSnapshot`).
    public static func breakReminderMinutesIfEnabled(in defaults: UserDefaults) -> Int? {
        breakReminderEnabled(in: defaults) ? breakReminderMinutes(in: defaults) : nil
    }
}
