import Foundation

/// Womit Takt Musik zum Timer abspielt. Wahl in den Einstellungen; die Steuerung selbst
/// liegt in der App (Musiksteuerung).
public enum MusicProvider: String, CaseIterable, Codable, Sendable {
    /// Spotify-Desktop-App per Apple Events.
    case spotify
    /// Apple Music (Musik-App) per Apple Events.
    case appleMusic
    /// Link im Standardbrowser öffnen (z. B. YouTube Music); Pause per Medientaste.
    case browser
    /// Keine Musiksteuerung.
    case none

    /// Name in den Einstellungen.
    public var title: String {
        switch self {
        case .spotify: "Spotify"
        case .appleMusic: "Apple Music"
        case .browser: "Browser"
        case .none: "Keine"
        }
    }
}
