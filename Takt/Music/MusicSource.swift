import Foundation
import TaktCore

/// Was zu einem Projekt abgespielt wird. Gespeichert als Text in `Project.musicSource`
/// bzw. `AppSettings.defaultPlaylistURI` (siehe `storageString`).
enum MusicSource: Hashable, Sendable {
    /// `spotify:playlist:…`, `spotify:album:…`, `spotify:track:…`
    case spotify(uri: String)
    /// Link auf den Apple-Music-Katalog (`https://music.apple.com/…` oder `music://…`).
    case appleMusicURL(URL)
    /// Playlist aus der eigenen Mediathek der Musik-App, per Name.
    case appleMusicPlaylist(name: String)
    /// Beliebiger Web-Link (YouTube, YouTube Music, SoundCloud, …) – öffnet im Standardbrowser.
    case web(URL)

    /// Präfix der gespeicherten Form für Apple-Music-Playlists.
    static let appleMusicPlaylistPrefix = "applemusic:playlist:"
    /// Bequeme Eingabe im Feld: „Apple Music: Fokus“.
    private static let appleMusicShortPrefix = "apple music:"

    private static let appleMusicHosts: Set<String> = ["music.apple.com", "itunes.apple.com", "geo.music.apple.com"]
    private static let appleMusicSchemes: Set<String> = ["music", "musics", "itms", "itmss"]
    private static let youTubeMusicHosts: Set<String> = ["music.youtube.com"]
    private static let youTubeHosts: Set<String> = ["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"]

    // MARK: Erkennung

    /// Erkennt eine Quelle aus Nutzereingabe oder gespeichertem Text.
    ///
    /// - `spotify:…` und `open.spotify.com/{playlist|album|track}/ID` → `.spotify` (Links werden zu URIs)
    /// - `applemusic:playlist:Name` oder `Apple Music: Name` → `.appleMusicPlaylist`
    /// - `music.apple.com/…`, `music://…` → `.appleMusicURL`
    /// - sonstige `http(s)`-Links (auch ohne Schema, z. B. `youtu.be/…`) → `.web`
    /// - Bloßer Name ohne Präfix: nur wenn `provider == .appleMusic` eine Playlist, sonst `nil`.
    /// - Leerer oder unbrauchbarer Text → `nil`
    static func parse(_ input: String, preferring provider: MusicProvider? = nil) -> MusicSource? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()

        if lower.hasPrefix("spotify:") {
            // Mindestens „spotify:art:id“; der Rest bleibt wie eingegeben (IDs sind case-sensitiv).
            let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count >= 3, parts.dropFirst().allSatisfy({ !$0.isEmpty }),
                  !text.contains(where: \.isWhitespace) else { return nil }
            return .spotify(uri: text)
        }
        if lower.hasPrefix(appleMusicPlaylistPrefix) {
            return playlist(named: text.dropFirst(appleMusicPlaylistPrefix.count))
        }
        if lower.hasPrefix(appleMusicShortPrefix) {
            return playlist(named: text.dropFirst(appleMusicShortPrefix.count))
        }

        if let url = link(from: text) {
            let scheme = url.scheme?.lowercased() ?? ""
            let host = url.host?.lowercased() ?? ""
            if appleMusicSchemes.contains(scheme) {
                return host.isEmpty ? nil : .appleMusicURL(url)
            }
            if SpotifyLink.isSpotifyHost(host) {
                // Spotify-Links nur, wenn sie sich wie bisher in eine URI umwandeln lassen.
                return SpotifyLink.uri(from: url).map { .spotify(uri: $0) }
            }
            if appleMusicHosts.contains(host) { return .appleMusicURL(url) }
            return .web(url)
        }

        // Kein Link: als Playlist-Name nur, wenn Apple Music der bevorzugte Anbieter ist.
        if provider == .appleMusic, !text.contains("://") {
            return playlist(named: Substring(text))
        }
        return nil
    }

    /// Text für die Speicherung; `parse(storageString)` ergibt wieder dieselbe Quelle.
    var storageString: String {
        switch self {
        case .spotify(let uri): uri
        case .appleMusicURL(let url): url.absoluteString
        case .appleMusicPlaylist(let name): Self.appleMusicPlaylistPrefix + name
        case .web(let url): url.absoluteString
        }
    }

    // MARK: Anzeige

    /// Art der Quelle für Hinweise in der Oberfläche.
    var displayName: String {
        switch self {
        case .spotify(let uri):
            switch uri.split(separator: ":").dropFirst().first?.lowercased() {
            case "album": "Spotify-Album"
            case "track": "Spotify-Titel"
            default: "Spotify-Playlist"
            }
        case .appleMusicURL, .appleMusicPlaylist:
            "Apple Music"
        case .web(let url):
            switch url.host?.lowercased() {
            case let host? where Self.youTubeMusicHosts.contains(host): "YouTube Music"
            case let host? where Self.youTubeHosts.contains(host): "YouTube"
            default: "Web-Link"
            }
        }
    }

    /// SF-Symbol passend zur Quelle.
    var systemImage: String {
        switch self {
        case .spotify: "music.note.list"
        case .appleMusicURL, .appleMusicPlaylist: "music.note"
        case .web(let url):
            if let host = url.host?.lowercased(),
               Self.youTubeHosts.contains(host) || Self.youTubeMusicHosts.contains(host) {
                "play.rectangle"
            } else {
                "globe"
            }
        }
    }

    /// Wer die Quelle abspielt.
    var provider: MusicProvider {
        switch self {
        case .spotify: .spotify
        case .appleMusicURL, .appleMusicPlaylist: .appleMusic
        case .web: .browser
        }
    }

    // MARK: Hilfen

    private static func playlist(named raw: Substring) -> MusicSource? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : .appleMusicPlaylist(name: name)
    }

    /// Link aus dem Text: mit Schema (`https://…`, `music://…`) oder als Domain ohne Schema
    /// (`youtu.be/…`, `music.apple.com/…`). Leerzeichen schließen einen Link aus.
    private static func link(from text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace) else { return nil }

        if let range = text.range(of: "://") {
            let scheme = text[..<range.lowerBound].lowercased()
            guard scheme == "http" || scheme == "https" || appleMusicSchemes.contains(scheme),
                  let url = URL(string: text), url.host?.isEmpty == false else { return nil }
            if scheme == "http" || scheme == "https" {
                return looksLikeDomain(url.host ?? "") ? url : nil
            }
            return url
        }

        // Ohne Schema nur, wenn der Teil vor dem ersten „/“ wie eine Domain aussieht.
        let hostPart = text.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        guard looksLikeDomain(hostPart), let url = URL(string: "https://" + text) else { return nil }
        return url
    }

    /// `name.tld` mit Buchstaben-TLD (mind. 2 Zeichen) oder `localhost`.
    private static func looksLikeDomain(_ host: String) -> Bool {
        let host = host.lowercased()
        if host == "localhost" { return true }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }),
              let tld = labels.last, tld.count >= 2, tld.allSatisfy({ $0.isASCII && $0.isLetter })
        else { return false }
        return host.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }
    }
}
