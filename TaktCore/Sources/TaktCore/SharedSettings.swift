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

/// Zustand des Pomodoro-Modus für das Widget. Die App schreibt ihn bei jedem Phasenwechsel nach
/// `SharedSettings.pomodoro`; das Widget rechnet die Restzeit aus `phaseEndsAt` selbst.
public struct PomodoroState: Codable, Sendable, Hashable {
    public enum Phase: String, Codable, Sendable, CaseIterable {
        case work
        case shortBreak
        case longBreak
        /// Modus an, aber gerade keine Einheit und keine Pause.
        case idle

        /// Unbekannte Werte (z. B. aus einer neueren App-Version) werden zu `.idle`.
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Phase(rawValue: raw) ?? .idle
        }

        public var isBreak: Bool { self == .shortBreak || self == .longBreak }

        /// Deutscher Name für die Oberfläche.
        public var title: String {
            switch self {
            case .work: "Arbeit"
            case .shortBreak: "Pause"
            case .longBreak: "Lange Pause"
            case .idle: "Bereit"
            }
        }
    }

    /// Pomodoro-Modus eingeschaltet (`AppSettings.pomodoroEnabled`).
    public var enabled: Bool
    public var phase: Phase
    /// Ende der laufenden Phase; `nil` bei `.idle`.
    public var phaseEndsAt: Date?
    /// Nummer der aktuellen bzw. zuletzt begonnenen Arbeitseinheit, ab 1.
    public var cycle: Int
    /// Einheiten bis zur langen Pause.
    public var cyclesBeforeLongBreak: Int
    /// Zeitpunkt, zu dem die App den Zustand geschrieben hat.
    public var updatedAt: Date

    public init(
        enabled: Bool,
        phase: Phase,
        phaseEndsAt: Date? = nil,
        cycle: Int = 1,
        cyclesBeforeLongBreak: Int = 4,
        updatedAt: Date = .now
    ) {
        self.enabled = enabled
        self.phase = phase
        self.phaseEndsAt = phaseEndsAt
        self.cycle = cycle
        self.cyclesBeforeLongBreak = cyclesBeforeLongBreak
        self.updatedAt = updatedAt
    }

    /// Restzeit der Phase zu `date`, nie negativ; `nil` ohne Phasenende.
    public func remaining(at date: Date) -> TimeInterval? {
        phaseEndsAt.map { max(0, $0.timeIntervalSince(date)) }
    }

    /// Phase läuft zu `date` noch (Ende in der Zukunft).
    public func isActive(at date: Date) -> Bool {
        guard phase != .idle, let phaseEndsAt else { return false }
        return phaseEndsAt > date
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
    /// Schlüssel des Wochenziels in Stunden (Spiegel von `AppSettings`).
    public static let weeklyGoalHoursKey = "weeklyGoalHours"
    /// Schlüssel des Pomodoro-Zustands (JSON von `PomodoroState`).
    public static let pomodoroKey = "pomodoroState"

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

    // MARK: Wochenziel

    /// Wochenziel in Stunden (für eine volle Woche mit fünf Arbeitstagen); `nil` = kein Ziel.
    public static var weeklyGoalHours: Double? {
        get { weeklyGoalHours(in: defaults) }
        set { setWeeklyGoalHours(newValue, in: defaults) }
    }

    /// Fehlende oder unsinnige Werte (≤ 0, über 168 h, nicht endlich) ergeben `nil`.
    public static func weeklyGoalHours(in defaults: UserDefaults) -> Double? {
        guard let value = (defaults.object(forKey: weeklyGoalHoursKey) as? NSNumber)?.doubleValue else { return nil }
        return validWeeklyGoalHours(value)
    }

    /// Schreibt das Ziel; `nil` (oder ein unsinniger Wert) entfernt es.
    public static func setWeeklyGoalHours(_ hours: Double?, in defaults: UserDefaults) {
        if let hours = hours.flatMap(validWeeklyGoalHours) {
            defaults.set(hours, forKey: weeklyGoalHoursKey)
        } else {
            defaults.removeObject(forKey: weeklyGoalHoursKey)
        }
    }

    /// Wochenziel in Sekunden für `report(…weeklyGoal:…)`, `nil` ohne Ziel.
    public static func weeklyGoal(in defaults: UserDefaults) -> TimeInterval? {
        weeklyGoalHours(in: defaults).map { $0 * 3600 }
    }

    /// `hours`, falls 0 < hours ≤ 168 (eine Woche), sonst `nil`.
    public static func validWeeklyGoalHours(_ hours: Double) -> Double? {
        hours.isFinite && hours > 0 && hours <= 168 ? hours : nil
    }

    // MARK: Pomodoro

    /// Pomodoro-Zustand für das Widget; `nil` = nie geschrieben oder gelöscht.
    public static var pomodoro: PomodoroState? {
        get { pomodoro(in: defaults) }
        set { setPomodoro(newValue, in: defaults) }
    }

    /// Fehlende oder unlesbare Werte ergeben `nil`.
    public static func pomodoro(in defaults: UserDefaults) -> PomodoroState? {
        guard let data = defaults.data(forKey: pomodoroKey) else { return nil }
        return try? JSONDecoder().decode(PomodoroState.self, from: data)
    }

    /// Schreibt den Zustand als JSON; `nil` entfernt ihn.
    public static func setPomodoro(_ state: PomodoroState?, in defaults: UserDefaults) {
        guard let state, let data = try? JSONEncoder().encode(state) else {
            defaults.removeObject(forKey: pomodoroKey)
            return
        }
        defaults.set(data, forKey: pomodoroKey)
    }

    /// Entfernt den Pomodoro-Zustand (z. B. beim Ausschalten des Modus).
    public static func clearPomodoro(in defaults: UserDefaults = SharedSettings.defaults) {
        defaults.removeObject(forKey: pomodoroKey)
    }

    /// Zustand für `WidgetSnapshot`: nur bei eingeschaltetem Modus.
    public static func pomodoroIfEnabled(in defaults: UserDefaults) -> PomodoroState? {
        pomodoro(in: defaults).flatMap { $0.enabled ? $0 : nil }
    }
}
