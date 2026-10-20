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
            SharedSettings.breakReminderEnabled = breakReminderEnabled
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

    // MARK: Widget

    /// Standardstil für neue Widgets. Liegt nicht in `defaults`, sondern in der App-Group-Suite
    /// (`SharedSettings`), damit die Widget-Extension sie lesen kann.
    var widgetStyle: WidgetStyle { didSet { SharedSettings.widgetStyle = widgetStyle } }

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
    }

    /// Standard-Kurzbefehl: ⌃⌥⌘T.
    static let defaultShortcutKeyCode = 17
    static let defaultShortcutModifiers = NSEvent.ModifierFlags([.control, .option, .command]).rawValue
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

        // `didSet` greift in `init` nicht: Pausenerinnerung einmal beim Start für das Widget spiegeln.
        SharedSettings.breakReminderEnabled = breakReminderEnabled
        SharedSettings.breakReminderMinutes = breakReminderMinutes
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
