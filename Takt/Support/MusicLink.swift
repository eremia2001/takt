import Foundation
import TaktCore

/// Auswertung eines Musik-Eingabefelds (Projekt-Editor, Einstellungen).
///
/// Unterscheidet „leer“ (keine Quelle) von „nicht erkannt“; die eigentliche Erkennung
/// liegt in `MusicSource.parse`.
enum MusicLink {
    enum Result: Equatable {
        /// Feld leer → keine Quelle.
        case empty
        /// Erkannte Quelle.
        case valid(MusicSource)
        /// Text, mit dem keine Quelle gemeint sein kann.
        case invalid
    }

    /// - Parameter preferring: bevorzugter Anbieter für mehrdeutige Eingaben
    ///   (ein bloßer Name gilt bei Apple Music als Playlist-Name).
    static func parse(_ input: String, preferring provider: MusicProvider? = nil) -> Result {
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .empty }
        return MusicSource.parse(input, preferring: provider).map(Result.valid) ?? .invalid
    }

    /// Hinweistext unter dem Eingabefeld, z. B. „Spotify-Playlist“ oder „Apple Music · Playlist „Fokus““.
    static func summary(of source: MusicSource) -> String {
        switch source {
        case .appleMusicPlaylist(let name):
            "\(source.displayName) · Playlist „\(name)“ aus der Mediathek"
        case .appleMusicURL:
            "\(source.displayName) · Link, öffnet in der Musik-App"
        case .web(let url):
            if source.displayName == "Web-Link", let host = url.host {
                "\(source.displayName) · \(host), öffnet im Browser"
            } else {
                "\(source.displayName) · öffnet im Browser"
            }
        case .spotify:
            source.displayName
        }
    }

    /// Hinweis bei nicht erkannter Eingabe.
    static let invalidHint = "Nicht erkannt. Möglich: Spotify-, Apple-Music- oder YouTube-Link, andere Web-Adresse oder „Apple Music: Playlist-Name“."
}

/// Wandelt Spotify-Web-Links in `spotify:`-URIs um.
enum SpotifyLink {
    /// Unterstützte Arten in Web-Links.
    static let kinds: Set<String> = ["playlist", "album", "track"]

    /// Ob der Host zu Spotify gehört (dann muss der Link umwandelbar sein).
    static func isSpotifyHost(_ host: String) -> Bool {
        host == "open.spotify.com" || host == "play.spotify.com"
    }

    /// - `https://open.spotify.com/playlist/ID?si=…` → `spotify:playlist:ID`
    ///   (ebenso `album`, `track`, auch mit Sprachpfad wie `/intl-de/`)
    /// - sonst `nil`
    static func uri(from url: URL) -> String? {
        guard let host = url.host?.lowercased(), isSpotifyHost(host) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        for (index, part) in parts.enumerated() where kinds.contains(part.lowercased()) {
            guard index + 1 < parts.count else { return nil }
            let id = parts[index + 1]
            guard !id.isEmpty, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
                return nil
            }
            return "spotify:\(part.lowercased()):\(id)"
        }
        return nil
    }
}
