import Foundation

/// Wandelt eingegebene Spotify-Links in `spotify:`-URIs um.
enum SpotifyLink {
    enum Result: Equatable {
        /// Feld leer → keine Playlist.
        case empty
        /// Gültige URI, z. B. `spotify:playlist:37i9dQZF1DX…`.
        case valid(String)
        /// Weder `spotify:`-URI noch erkennbarer Spotify-Link.
        case invalid
    }

    /// Unterstützte Arten in Web-Links.
    private static let kinds: Set<String> = ["playlist", "album", "track"]

    /// - `https://open.spotify.com/playlist/ID?si=…` → `spotify:playlist:ID`
    ///   (ebenso `album`, `track`, auch mit Sprachpfad wie `/intl-de/`)
    /// - `spotify:…` → unverändert
    /// - leer → `.empty`
    static func parse(_ input: String) -> Result {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .empty }
        if text.lowercased().hasPrefix("spotify:") { return .valid(text) }

        // Links ohne Schema („open.spotify.com/…“) ebenfalls akzeptieren.
        let withScheme = text.contains("://") ? text : "https://" + text
        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased(), host == "open.spotify.com" || host == "play.spotify.com"
        else { return .invalid }

        let parts = url.pathComponents.filter { $0 != "/" }
        for (index, part) in parts.enumerated() where kinds.contains(part.lowercased()) {
            guard index + 1 < parts.count else { return .invalid }
            let id = parts[index + 1]
            guard !id.isEmpty, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
                return .invalid
            }
            return .valid("spotify:\(part.lowercased()):\(id)")
        }
        return .invalid
    }
}
