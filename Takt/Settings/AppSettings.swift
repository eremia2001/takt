import Foundation
import Observation
import TaktCore

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

    var breakReminderEnabled: Bool {
        didSet { defaults.set(breakReminderEnabled, forKey: Key.breakReminderEnabled) }
    }
    /// Minuten nach Timer-Start bis zur Erinnerung.
    var breakReminderMinutes: Int {
        didSet { defaults.set(breakReminderMinutes, forKey: Key.breakReminderMinutes) }
    }
    /// Bei der Pausenerinnerung Musik pausieren.
    var breakPausesMusic: Bool { didSet { defaults.set(breakPausesMusic, forKey: Key.breakPausesMusic) } }

    // MARK: Timer

    /// Grenze in Stunden, ab der bei einem laufenden Timer nachgefragt wird (Logik folgt später).
    var forgottenTimerHours: Int {
        didSet { defaults.set(forgottenTimerHours, forKey: Key.forgottenTimerHours) }
    }

    // MARK: Widget

    /// Darstellung des Widgets. Liegt nicht in `defaults`, sondern in der App-Group-Suite
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
    }

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
    }

    /// Schützt vor unsinnigen Werten (z. B. von Hand per `defaults write` gesetzt).
    private static func clamp(_ value: Int, _ range: ClosedRange<Int>, fallback: Int) -> Int {
        range.contains(value) ? value : fallback
    }
}
