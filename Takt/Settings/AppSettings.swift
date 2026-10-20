import AppKit
import Foundation
import Observation
import TaktCore
import WidgetKit

/// App-Einstellungen, dauerhaft in `UserDefaults` (Schlüssel mit Präfix `settings.`).
/// Jede Änderung wird sofort gespeichert.
@MainActor
@Observable
final class AppSettings {
    // MARK: Musik

    /// Globaler Schalter: Spotify beim Starten/Stoppen von Timern steuern.
    var musicEnabled: Bool { didSet { defaults.set(musicEnabled, forKey: Key.musicEnabled) } }
    /// Playlist für Projekte ohne eigene, als `spotify:`-URI.
    var defaultPlaylistURI: String? {
        didSet {
            if let defaultPlaylistURI, !defaultPlaylistURI.isEmpty {
                defaults.set(defaultPlaylistURI, forKey: Key.defaultPlaylistURI)
            } else {
                defaults.removeObject(forKey: Key.defaultPlaylistURI)
            }
        }
    }
    /// Beim Stoppen des Timers laufende Musik pausieren.
    var pauseOnStop: Bool { didSet { defaults.set(pauseOnStop, forKey: Key.pauseOnStop) } }
    /// Wenn `false` und Spotify spielt schon etwas, beim Timer-Start nicht umschalten.
    var takeOverPlayingMusic: Bool {
        didSet { defaults.set(takeOverPlayingMusic, forKey: Key.takeOverPlayingMusic) }
    }

    // MARK: Pausen

    /// Wird zusätzlich in die App-Group-Suite gespiegelt (`SharedSettings`), damit das Widget
    /// die Erinnerung anzeigen kann.
    var breakReminderEnabled: Bool {
        didSet {
            defaults.set(breakReminderEnabled, forKey: Key.breakReminderEnabled)
            SharedSettings.breakReminderEnabled = breakReminderEnabled && !pomodoroEnabled
            if breakReminderEnabled != oldValue { WidgetCenter.shared.reloadAllTimelines() }
        }
    }
    /// Minuten nach Timer-Start bis zur Erinnerung (ebenfalls gespiegelt).
    var breakReminderMinutes: Int {
        didSet {
            defaults.set(breakReminderMinutes, forKey: Key.breakReminderMinutes)
            SharedSettings.breakReminderMinutes = breakReminderMinutes
            if breakReminderMinutes != oldValue { WidgetCenter.shared.reloadAllTimelines() }
        }
    }
    /// Bei der Pausenerinnerung Musik pausieren.
    var breakPausesMusic: Bool { didSet { defaults.set(breakPausesMusic, forKey: Key.breakPausesMusic) } }

    // MARK: Leerlauf & Pomodoro (Fokus v2)

    /// Leerlauf-Erkennung: nach `idleMinutes` ohne Eingabe bei laufendem Timer nachfragen.
    var idleDetectionEnabled: Bool {
        didSet { defaults.set(idleDetectionEnabled, forKey: Key.idleDetectionEnabled) }
    }
    /// Minuten ohne Tastatur/Maus, ab denen Leerlauf gilt (1–120, Standard 10).
    var idleMinutes: Int { didSet { defaults.set(idleMinutes, forKey: Key.idleMinutes) } }
    /// Pomodoro-Modus eingeschaltet.
    var pomodoroEnabled: Bool {
        didSet {
            defaults.set(pomodoroEnabled, forKey: Key.pomodoroEnabled)
            // Bei aktivem Pomodoro zeigt das Widget keinen Pausenfortschritt der normalen Erinnerung.
            SharedSettings.breakReminderEnabled = breakReminderEnabled && !pomodoroEnabled
            // Ausgeschaltet: kein Pomodoro-Zustand mehr im Widget (den Zustand schreibt sonst
            // `PomodoroController` bei jedem Phasenwechsel).
            if !pomodoroEnabled { SharedSettings.clearPomodoro() }
            if pomodoroEnabled != oldValue { WidgetCenter.shared.reloadAllTimelines() }
        }
    }
    /// Länge einer Arbeitseinheit in Minuten (5–180, Standard 50).
    var pomodoroWorkMinutes: Int {
        didSet { defaults.set(pomodoroWorkMinutes, forKey: Key.pomodoroWorkMinutes) }
    }
    /// Kurze Pause in Minuten (1–60, Standard 10).
    var pomodoroBreakMinutes: Int {
        didSet { defaults.set(pomodoroBreakMinutes, forKey: Key.pomodoroBreakMinutes) }
    }
    /// Lange Pause in Minuten (1–120, Standard 20).
    var pomodoroLongBreakMinutes: Int {
        didSet { defaults.set(pomodoroLongBreakMinutes, forKey: Key.pomodoroLongBreakMinutes) }
    }
    /// Arbeitseinheiten bis zur langen Pause (1–12, Standard 4).
    var pomodoroCyclesBeforeLongBreak: Int {
        didSet { defaults.set(pomodoroCyclesBeforeLongBreak, forKey: Key.pomodoroCyclesBeforeLongBreak) }
    }
    /// Am Ende einer Arbeitseinheit den Timer stoppen (Pause wird nicht erfasst).
    var pomodoroAutoStopTimer: Bool {
        didSet { defaults.set(pomodoroAutoStopTimer, forKey: Key.pomodoroAutoStopTimer) }
    }

    // MARK: Wochenziel

    /// Wochenziel in Stunden (für fünf Arbeitstage; freie Tage verringern es anteilig);
    /// `nil` = kein Ziel. Wird in die App-Group-Suite gespiegelt (`SharedSettings`), damit das
    /// Widget es später anzeigen kann.
    var weeklyGoalHours: Double? {
        didSet {
            let valid = weeklyGoalHours.flatMap(SharedSettings.validWeeklyGoalHours)
            if let valid {
                defaults.set(valid, forKey: Key.weeklyGoalHours)
            } else {
                defaults.removeObject(forKey: Key.weeklyGoalHours)
            }
            SharedSettings.weeklyGoalHours = valid
            if valid != oldValue.flatMap(SharedSettings.validWeeklyGoalHours) {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    /// Wochenziel in Sekunden für Berichte, `nil` ohne (gültiges) Ziel.
    var weeklyGoal: TimeInterval? {
        weeklyGoalHours.flatMap(SharedSettings.validWeeklyGoalHours).map { $0 * 3600 }
    }

    // MARK: Timer

    /// Grenze in Stunden, ab der bei einem laufenden Timer nachgefragt wird (Logik folgt später).
    var forgottenTimerHours: Int {
        didSet { defaults.set(forgottenTimerHours, forKey: Key.forgottenTimerHours) }
    }

    // MARK: Abrechnung

    /// Rundung abrechenbarer Zeiten in Berichten und Export (aufwärts je Eintrag).
    var rounding: Rounding { didSet { defaults.set(rounding.rawValue, forKey: Key.rounding) } }
    /// Währung als ISO-4217-Code aus drei Großbuchstaben, z. B. „EUR“.
    var currencyCode: String {
        didSet {
            let valid = Self.validCurrencyCode(currencyCode)
            // Ungültiges nicht speichern; der zuletzt gültige Wert bleibt erhalten.
            if let valid { defaults.set(valid, forKey: Key.currencyCode) }
        }
    }
    /// Stundensatz für Projekte ohne eigenen Satz; `nil` = keiner.
    /// Gespeichert als Text in POSIX-Schreibweise („85.5“), wie in der Datenbank.
    var defaultHourlyRate: Decimal? {
        didSet {
            if let defaultHourlyRate {
                defaults.set(NSDecimalNumber(decimal: defaultHourlyRate).description(withLocale: Self.posix),
                             forKey: Key.defaultHourlyRate)
            } else {
                defaults.removeObject(forKey: Key.defaultHourlyRate)
            }
        }
    }

    // MARK: Musikquelle

    /// Womit Musik gespielt wird (Spotify, Apple Music, Browser oder gar nicht).
    var musicProvider: MusicProvider {
        didSet { defaults.set(musicProvider.rawValue, forKey: Key.musicProvider) }
    }
    /// Browser-Quelle: beim Stoppen per Medientaste (Play/Pause) pausieren.
    var browserPauseWithMediaKey: Bool {
        didSet { defaults.set(browserPauseWithMediaKey, forKey: Key.browserPauseWithMediaKey) }
    }

    // MARK: Allgemein

    /// Symbol in der Menüleiste anzeigen.
    var menuBarEnabled: Bool { didSet { defaults.set(menuBarEnabled, forKey: Key.menuBarEnabled) } }
    /// Dock-Symbol ausblenden (nur sinnvoll mit Menüleiste).
    var hideDockIcon: Bool { didSet { defaults.set(hideDockIcon, forKey: Key.hideDockIcon) } }
    /// Globaler Kurzbefehl Start/Stopp aktiv.
    var globalShortcutEnabled: Bool {
        didSet { defaults.set(globalShortcutEnabled, forKey: Key.globalShortcutEnabled) }
    }
    /// Virtueller Tastencode (Carbon `kVK_…`) des Kurzbefehls; Standard 17 = „T“.
    var globalShortcutKeyCode: Int {
        didSet { defaults.set(globalShortcutKeyCode, forKey: Key.globalShortcutKeyCode) }
    }
    /// Modifikatoren als `NSEvent.ModifierFlags.rawValue`; Standard ⌃⌥⌘.
    var globalShortcutModifiers: UInt {
        didSet { defaults.set(globalShortcutModifiers, forKey: Key.globalShortcutModifiers) }
    }

    // MARK: Menüleiste (Stile)

    /// Darstellung in der Menüleiste (Symbol, Kompakt, Text, Kapsel, Ring); Standard Text.
    var menuBarStyle: MenuBarStyle {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: Key.menuBarStyle) }
    }
    /// Projektname in Text- und Kapsel-Stil zeigen.
    var menuBarShowProjectName: Bool {
        didSet { defaults.set(menuBarShowProjectName, forKey: Key.menuBarShowProjectName) }
    }
    /// Tagessumme statt Laufzeit des aktuellen Eintrags zeigen.
    var menuBarShowTodayTotal: Bool {
        didSet { defaults.set(menuBarShowTodayTotal, forKey: Key.menuBarShowTodayTotal) }
    }
    /// Darstellung, wenn nichts läuft (nur Symbol, mit Tagessumme, ausgeblendet).
    var menuBarIdleMode: MenuBarIdleMode {
        didSet { defaults.set(menuBarIdleMode.rawValue, forKey: Key.menuBarIdleMode) }
    }

    // MARK: Widget

    /// Standardstil für neue Widgets. Liegt nicht in `defaults`, sondern in der App-Group-Suite
    /// (`SharedSettings`), damit die Widget-Extension sie lesen kann.
    var widgetStyle: WidgetStyle { didSet { SharedSettings.widgetStyle = widgetStyle } }

    // MARK: Kalender (v5)

    /// Kalenderereignisse in „Heute“ anzeigen. Aus, bis die Berechtigung erteilt ist.
    var calendarShowEvents: Bool {
        didSet { defaults.set(calendarShowEvents, forKey: Key.calendarShowEvents) }
    }
    /// Angezeigte Kalender (`EKCalendar.calendarIdentifier`); leer = alle.
    var calendarVisibleIDs: [String] {
        didSet { defaults.set(calendarVisibleIDs, forKey: Key.calendarVisibleIDs) }
    }
    /// Abgeschlossene Einträge in einen Kalender spiegeln.
    var calendarMirrorEnabled: Bool {
        didSet { defaults.set(calendarMirrorEnabled, forKey: Key.calendarMirrorEnabled) }
    }
    /// Zielkalender der Spiegelung; `nil` = noch keiner gewählt.
    var calendarMirrorCalendarID: String? {
        didSet {
            if let calendarMirrorCalendarID, !calendarMirrorCalendarID.isEmpty {
                defaults.set(calendarMirrorCalendarID, forKey: Key.calendarMirrorCalendarID)
            } else {
                defaults.removeObject(forKey: Key.calendarMirrorCalendarID)
            }
        }
    }
    /// Kürzere Einträge werden nicht gespiegelt (1–240 Minuten, Standard 5).
    var calendarMirrorMinimumMinutes: Int {
        didSet { defaults.set(calendarMirrorMinimumMinutes, forKey: Key.calendarMirrorMinimumMinutes) }
    }

    // MARK: Aktivität (v5)

    /// Projektvorschläge aus der beobachteten Aktivität (App, Fenster, Repository).
    var activitySuggestionsEnabled: Bool {
        didSet { defaults.set(activitySuggestionsEnabled, forKey: Key.activitySuggestionsEnabled) }
    }
    /// Minuten, die die Aktivität zu einem anderen Projekt passen muss, bevor Takt nachfragt
    /// (1–120, Standard 10).
    var activityMismatchMinutes: Int {
        didSet { defaults.set(activityMismatchMinutes, forKey: Key.activityMismatchMinutes) }
    }
    /// Ohne laufenden Timer bei passender Aktivität automatisch starten.
    var activityAutoStartEnabled: Bool {
        didSet { defaults.set(activityAutoStartEnabled, forKey: Key.activityAutoStartEnabled) }
    }

    // MARK: Budget (v5)

    /// Hinweis, wenn ein Projekt 80 % bzw. 100 % seines Stundenbudgets erreicht.
    var budgetWarningsEnabled: Bool {
        didSet { defaults.set(budgetWarningsEnabled, forKey: Key.budgetWarningsEnabled) }
    }

    // MARK: Schnelleingabe überall (v5)

    /// Globaler Kurzbefehl für die Schnelleingabe.
    var quickEntryHotKeyEnabled: Bool {
        didSet { defaults.set(quickEntryHotKeyEnabled, forKey: Key.quickEntryHotKeyEnabled) }
    }
    /// Virtueller Tastencode (Carbon `kVK_…`); Standard 45 = „N“.
    var quickEntryHotKeyKeyCode: Int {
        didSet { defaults.set(quickEntryHotKeyKeyCode, forKey: Key.quickEntryHotKeyKeyCode) }
    }
    /// Modifikatoren als `NSEvent.ModifierFlags.rawValue`; Standard ⌃⌥⌘.
    var quickEntryHotKeyModifiers: UInt {
        didSet { defaults.set(quickEntryHotKeyModifiers, forKey: Key.quickEntryHotKeyModifiers) }
    }
    /// Eingabefeld für die Schnelleingabe im Menüleisten-Popover.
    var quickEntryInMenuBar: Bool {
        didSet { defaults.set(quickEntryInMenuBar, forKey: Key.quickEntryInMenuBar) }
    }

    // MARK: Interna

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let musicEnabled = "settings.musicEnabled"
        static let defaultPlaylistURI = "settings.defaultPlaylistURI"
        static let pauseOnStop = "settings.pauseOnStop"
        static let takeOverPlayingMusic = "settings.takeOverPlayingMusic"
        static let breakReminderEnabled = "settings.breakReminderEnabled"
        static let breakReminderMinutes = "settings.breakReminderMinutes"
        static let breakPausesMusic = "settings.breakPausesMusic"
        static let forgottenTimerHours = "settings.forgottenTimerHours"
        static let rounding = "settings.rounding"
        static let currencyCode = "settings.currencyCode"
        static let defaultHourlyRate = "settings.defaultHourlyRate"
        static let musicProvider = "settings.musicProvider"
        static let browserPauseWithMediaKey = "settings.browserPauseWithMediaKey"
        static let menuBarEnabled = "settings.menuBarEnabled"
        static let hideDockIcon = "settings.hideDockIcon"
        static let globalShortcutEnabled = "settings.globalShortcutEnabled"
        static let globalShortcutKeyCode = "settings.globalShortcutKeyCode"
        static let globalShortcutModifiers = "settings.globalShortcutModifiers"
        static let idleDetectionEnabled = "settings.idleDetectionEnabled"
        static let idleMinutes = "settings.idleMinutes"
        static let pomodoroEnabled = "settings.pomodoroEnabled"
        static let pomodoroWorkMinutes = "settings.pomodoroWorkMinutes"
        static let pomodoroBreakMinutes = "settings.pomodoroBreakMinutes"
        static let pomodoroLongBreakMinutes = "settings.pomodoroLongBreakMinutes"
        static let pomodoroCyclesBeforeLongBreak = "settings.pomodoroCyclesBeforeLongBreak"
        static let pomodoroAutoStopTimer = "settings.pomodoroAutoStopTimer"
        static let weeklyGoalHours = "settings.weeklyGoalHours"
        static let calendarShowEvents = "settings.calendarShowEvents"
        static let calendarVisibleIDs = "settings.calendarVisibleIDs"
        static let calendarMirrorEnabled = "settings.calendarMirrorEnabled"
        static let calendarMirrorCalendarID = "settings.calendarMirrorCalendarID"
        static let calendarMirrorMinimumMinutes = "settings.calendarMirrorMinimumMinutes"
        static let activitySuggestionsEnabled = "settings.activitySuggestionsEnabled"
        static let activityMismatchMinutes = "settings.activityMismatchMinutes"
        static let activityAutoStartEnabled = "settings.activityAutoStartEnabled"
        static let budgetWarningsEnabled = "settings.budgetWarningsEnabled"
        static let quickEntryHotKeyEnabled = "settings.quickEntryHotKeyEnabled"
        static let quickEntryHotKeyKeyCode = "settings.quickEntryHotKeyKeyCode"
        static let quickEntryHotKeyModifiers = "settings.quickEntryHotKeyModifiers"
        static let quickEntryInMenuBar = "settings.quickEntryInMenuBar"
        static let menuBarStyle = "settings.menuBarStyle"
        static let menuBarShowProjectName = "settings.menuBarShowProjectName"
        static let menuBarShowTodayTotal = "settings.menuBarShowTodayTotal"
        static let menuBarIdleMode = "settings.menuBarIdleMode"
    }

    /// Standard-Kurzbefehl: ⌃⌥⌘T.
    static let defaultShortcutKeyCode = 17
    static let defaultShortcutModifiers = NSEvent.ModifierFlags([.control, .option, .command]).rawValue
    /// Standard-Kurzbefehl der Schnelleingabe: ⌃⌥⌘N.
    static let defaultQuickEntryKeyCode = 45
    static let defaultQuickEntryModifiers = defaultShortcutModifiers
    static let defaultCurrencyCode = "EUR"
    private static let posix = Locale(identifier: "en_US_POSIX")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Standardwerte gelten nur, solange der Nutzer nichts geändert hat.
        defaults.register(defaults: [
            Key.musicEnabled: true,
            Key.pauseOnStop: true,
            Key.takeOverPlayingMusic: true,
            Key.breakReminderEnabled: true,
            Key.breakReminderMinutes: 75,
            Key.breakPausesMusic: true,
            Key.forgottenTimerHours: 8,
            Key.rounding: Rounding.none.rawValue,
            Key.currencyCode: Self.defaultCurrencyCode,
            Key.musicProvider: MusicProvider.spotify.rawValue,
            Key.browserPauseWithMediaKey: true,
            Key.menuBarEnabled: true,
            Key.hideDockIcon: false,
            Key.globalShortcutEnabled: true,
            Key.globalShortcutKeyCode: Self.defaultShortcutKeyCode,
            Key.globalShortcutModifiers: Self.defaultShortcutModifiers,
            Key.idleDetectionEnabled: true,
            Key.idleMinutes: 10,
            Key.pomodoroEnabled: false,
            Key.pomodoroWorkMinutes: 50,
            Key.pomodoroBreakMinutes: 10,
            Key.pomodoroLongBreakMinutes: 20,
            Key.pomodoroCyclesBeforeLongBreak: 4,
            Key.pomodoroAutoStopTimer: true,
            Key.calendarShowEvents: false,
            Key.calendarVisibleIDs: [String](),
            Key.calendarMirrorEnabled: false,
            Key.calendarMirrorMinimumMinutes: 5,
            Key.activitySuggestionsEnabled: false,
            Key.activityMismatchMinutes: 10,
            Key.activityAutoStartEnabled: false,
            Key.budgetWarningsEnabled: true,
            Key.quickEntryHotKeyEnabled: true,
            Key.quickEntryHotKeyKeyCode: Self.defaultQuickEntryKeyCode,
            Key.quickEntryHotKeyModifiers: Self.defaultQuickEntryModifiers,
            Key.quickEntryInMenuBar: true,
            Key.menuBarStyle: MenuBarStyle.text.rawValue,
            Key.menuBarShowProjectName: true,
            Key.menuBarShowTodayTotal: false,
            Key.menuBarIdleMode: MenuBarIdleMode.symbol.rawValue,
        ])

        musicEnabled = defaults.bool(forKey: Key.musicEnabled)
        let storedPlaylist = defaults.string(forKey: Key.defaultPlaylistURI)
        defaultPlaylistURI = (storedPlaylist?.isEmpty ?? true) ? nil : storedPlaylist
        pauseOnStop = defaults.bool(forKey: Key.pauseOnStop)
        takeOverPlayingMusic = defaults.bool(forKey: Key.takeOverPlayingMusic)
        breakReminderEnabled = defaults.bool(forKey: Key.breakReminderEnabled)
        breakReminderMinutes = Self.clamp(defaults.integer(forKey: Key.breakReminderMinutes), 15...180, fallback: 75)
        breakPausesMusic = defaults.bool(forKey: Key.breakPausesMusic)
        forgottenTimerHours = Self.clamp(defaults.integer(forKey: Key.forgottenTimerHours), 1...24, fallback: 8)
        widgetStyle = SharedSettings.widgetStyle

        rounding = defaults.string(forKey: Key.rounding).flatMap(Rounding.init(rawValue:)) ?? .none
        currencyCode = Self.validCurrencyCode(defaults.string(forKey: Key.currencyCode) ?? "") ?? Self.defaultCurrencyCode
        defaultHourlyRate = defaults.string(forKey: Key.defaultHourlyRate)
            .flatMap { Decimal(string: $0, locale: Self.posix) }
        musicProvider = defaults.string(forKey: Key.musicProvider).flatMap(MusicProvider.init(rawValue:)) ?? .spotify
        browserPauseWithMediaKey = defaults.bool(forKey: Key.browserPauseWithMediaKey)
        menuBarEnabled = defaults.bool(forKey: Key.menuBarEnabled)
        hideDockIcon = defaults.bool(forKey: Key.hideDockIcon)
        globalShortcutEnabled = defaults.bool(forKey: Key.globalShortcutEnabled)
        globalShortcutKeyCode = Self.clamp(defaults.integer(forKey: Key.globalShortcutKeyCode), 0...127,
                                           fallback: Self.defaultShortcutKeyCode)
        let storedModifiers = (defaults.object(forKey: Key.globalShortcutModifiers) as? NSNumber)?.uintValue
        globalShortcutModifiers = (storedModifiers ?? 0) == 0 ? Self.defaultShortcutModifiers : storedModifiers!

        idleDetectionEnabled = defaults.bool(forKey: Key.idleDetectionEnabled)
        idleMinutes = Self.clamp(defaults.integer(forKey: Key.idleMinutes), 1...120, fallback: 10)
        pomodoroEnabled = defaults.bool(forKey: Key.pomodoroEnabled)
        pomodoroWorkMinutes = Self.clamp(defaults.integer(forKey: Key.pomodoroWorkMinutes), 5...180, fallback: 50)
        pomodoroBreakMinutes = Self.clamp(defaults.integer(forKey: Key.pomodoroBreakMinutes), 1...60, fallback: 10)
        pomodoroLongBreakMinutes = Self.clamp(defaults.integer(forKey: Key.pomodoroLongBreakMinutes), 1...120, fallback: 20)
        pomodoroCyclesBeforeLongBreak = Self.clamp(defaults.integer(forKey: Key.pomodoroCyclesBeforeLongBreak), 1...12, fallback: 4)
        pomodoroAutoStopTimer = defaults.bool(forKey: Key.pomodoroAutoStopTimer)
        weeklyGoalHours = (defaults.object(forKey: Key.weeklyGoalHours) as? NSNumber)
            .flatMap { SharedSettings.validWeeklyGoalHours($0.doubleValue) }

        calendarShowEvents = defaults.bool(forKey: Key.calendarShowEvents)
        calendarVisibleIDs = defaults.stringArray(forKey: Key.calendarVisibleIDs) ?? []
        calendarMirrorEnabled = defaults.bool(forKey: Key.calendarMirrorEnabled)
        let storedMirrorCalendar = defaults.string(forKey: Key.calendarMirrorCalendarID)
        calendarMirrorCalendarID = (storedMirrorCalendar?.isEmpty ?? true) ? nil : storedMirrorCalendar
        calendarMirrorMinimumMinutes = Self.clamp(defaults.integer(forKey: Key.calendarMirrorMinimumMinutes), 1...240, fallback: 5)
        activitySuggestionsEnabled = defaults.bool(forKey: Key.activitySuggestionsEnabled)
        activityMismatchMinutes = Self.clamp(defaults.integer(forKey: Key.activityMismatchMinutes), 1...120, fallback: 10)
        activityAutoStartEnabled = defaults.bool(forKey: Key.activityAutoStartEnabled)
        budgetWarningsEnabled = defaults.bool(forKey: Key.budgetWarningsEnabled)
        quickEntryHotKeyEnabled = defaults.bool(forKey: Key.quickEntryHotKeyEnabled)
        quickEntryHotKeyKeyCode = Self.clamp(defaults.integer(forKey: Key.quickEntryHotKeyKeyCode), 0...127,
                                             fallback: Self.defaultQuickEntryKeyCode)
        let storedQuickModifiers = (defaults.object(forKey: Key.quickEntryHotKeyModifiers) as? NSNumber)?.uintValue ?? 0
        quickEntryHotKeyModifiers = storedQuickModifiers == 0 ? Self.defaultQuickEntryModifiers : storedQuickModifiers
        quickEntryInMenuBar = defaults.bool(forKey: Key.quickEntryInMenuBar)
        menuBarStyle = defaults.string(forKey: Key.menuBarStyle).flatMap(MenuBarStyle.init(rawValue:)) ?? .text
        menuBarShowProjectName = defaults.bool(forKey: Key.menuBarShowProjectName)
        menuBarShowTodayTotal = defaults.bool(forKey: Key.menuBarShowTodayTotal)
        menuBarIdleMode = defaults.string(forKey: Key.menuBarIdleMode).flatMap(MenuBarIdleMode.init(rawValue:)) ?? .symbol

        // `didSet` greift in `init` nicht: Pausenerinnerung und Wochenziel einmal beim Start für das Widget spiegeln.
        SharedSettings.breakReminderEnabled = breakReminderEnabled && !pomodoroEnabled
        SharedSettings.breakReminderMinutes = breakReminderMinutes
        SharedSettings.weeklyGoalHours = weeklyGoalHours
        if !pomodoroEnabled { SharedSettings.clearPomodoro() }
    }

    /// Großgeschriebener Code, wenn `text` aus genau drei Buchstaben A–Z besteht, sonst `nil`.
    static func validCurrencyCode(_ text: String) -> String? {
        let code = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard code.count == 3, code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return code
    }

    /// Schützt vor unsinnigen Werten (z. B. von Hand per `defaults write` gesetzt).
    private static func clamp(_ value: Int, _ range: ClosedRange<Int>, fallback: Int) -> Int {
        range.contains(value) ? value : fallback
    }
}
