import AppKit
import Foundation
import TaktCore

/// Steuert die Musik-App (Apple Music) per Apple Events.
///
/// Am Rechner geprüft (macOS 26, Musik-App, `osascript`):
/// - `play playlist "<Name>"` spielt eine Playlist der eigenen Mediathek zuverlässig.
///   Unbekannter Name → Fehler -1700. Direkt nach dem Start der App wird der Befehl ohne
///   Fehler angenommen, spielt aber nicht – daher wie bei Spotify: `launch`, dann im
///   Sekundenabstand erneut versuchen und den `player state` prüfen.
/// - Katalog-Links (`https://music.apple.com/…`, `music://…`) lassen sich nur *öffnen*:
///   Die Musik-App zeigt Album/Playlist, spielt aber nicht. Ein anschließendes `play`
///   setzt den *vorherigen* Titel fort statt des Links und wird deshalb nicht gesendet.
///   `https://`-Links öffnet macOS im Browser; Takt öffnet sie daher als `music://`.
/// - `pause` und `player state` (`playing`/`paused`/`stopped`) funktionieren zuverlässig.
@MainActor
final class AppleMusicPlayer: MusicPlayer {
    let provider: MusicProvider = .appleMusic
    let canReadState = true

    private let runner: AppleScriptRunner
    private static let bundleID = "com.apple.Music"
    /// Nach dem Start der Musik-App: so oft (im Sekundenabstand) versuchen, die Playlist zu starten.
    private static let launchAttempts = 8
    /// Wartezeit nach dem Öffnen eines Links, bevor der Zustand geprüft wird.
    private static let linkSettleTime: Duration = .seconds(3)

    init(runner: AppleScriptRunner) {
        self.runner = runner
    }

    var isRunning: Bool { ScriptableApp.isRunning(bundleID: Self.bundleID) }

    func play(_ source: MusicSource) async throws {
        switch source {
        case .appleMusicPlaylist(let name):
            if isRunning {
                try await playPlaylist(name)
            } else {
                try await launchAndPlay(name)
            }
        case .appleMusicURL(let url):
            try await open(url)
        case .spotify, .web:
            throw MusicPlayerError.unsupportedSource(source)
        }
    }

    func pause() async {
        // Musik nicht starten, nur um zu pausieren.
        guard isRunning, await isPlaying(), !Task.isCancelled else { return }
        if case .failure(let error) = await runner.run(Scripts.pause) {
            MusicLog.logger.error("Musik: Pausieren fehlgeschlagen: \(error.description, privacy: .public)")
            return
        }
        MusicLog.logger.info("Musik pausiert.")
    }

    func isPlaying() async -> Bool {
        guard isRunning else { return false }
        switch await runner.run(Scripts.state) {
        case .success(let state):
            return state == "playing"
        case .failure(let error):
            MusicLog.logger.error("Musik-Status nicht lesbar: \(error.description, privacy: .public)")
            return false
        }
    }

    // MARK: Abläufe

    private func playPlaylist(_ name: String) async throws {
        if case .failure(let error) = await runner.run(Scripts.playPlaylist(name)) {
            if error.isObjectNotFound {
                throw MusicPlayerError.notPlaying("Musik: Playlist „\(name)“ nicht in der Mediathek gefunden.")
            }
            throw MusicPlayerError.script(error)
        }
        MusicLog.logger.info("Musik spielt Playlist „\(name, privacy: .public)“.")
    }

    /// Startet die Musik-App und versucht danach bis zu ~8 s lang, die Playlist abzuspielen.
    private func launchAndPlay(_ name: String) async throws {
        MusicLog.logger.info("Musik läuft nicht – wird gestartet.")
        if case .failure(let error) = await runner.run(Scripts.launch) {
            throw MusicPlayerError.script(error)
        }

        var lastError: AppleScriptError?
        for attempt in 1...Self.launchAttempts {
            try await Task.sleep(for: .seconds(1))

            switch await runner.run(Scripts.playPlaylist(name)) {
            case .success:
                // Kurz nach dem Start wird `play` teils angenommen, ohne zu spielen – prüfen.
                try await Task.sleep(for: .milliseconds(700))
                if await isPlaying() {
                    MusicLog.logger.info("Musik spielt Playlist „\(name, privacy: .public)“ (Versuch \(attempt)).")
                    return
                }
            case .failure(let error):
                if error.isPermissionDenied { throw MusicPlayerError.script(error) }
                // Mediathek evtl. noch nicht geladen – weiter versuchen.
                lastError = error
                MusicLog.logger.debug("Musik, Versuch \(attempt): \(error.description, privacy: .public)")
            }
        }
        if let lastError, lastError.isObjectNotFound {
            throw MusicPlayerError.notPlaying("Musik: Playlist „\(name)“ nicht in der Mediathek gefunden.")
        }
        throw MusicPlayerError.notPlaying("Musik hat „\(name)“ nach dem Start nicht abgespielt.")
    }

    /// Öffnet einen Katalog-Link in der Musik-App. Abspielen muss der Nutzer dort selbst.
    private func open(_ url: URL) async throws {
        // Laufende Musik anhalten, sonst spielt der alte Titel weiter, während der Link offen ist.
        if isRunning, await isPlaying() {
            try Task.checkCancellation()
            _ = await runner.run(Scripts.pause)
        }
        try Task.checkCancellation()

        let appURL = Self.musicAppURL(for: url)
        let configuration = NSWorkspace.OpenConfiguration()
        // Nach vorn holen: Der Nutzer muss dort ▶ drücken (siehe Typ-Kommentar).
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.open(appURL, configuration: configuration)
        } catch {
            throw MusicPlayerError.openFailed(appURL, error.localizedDescription)
        }

        try await Task.sleep(for: Self.linkSettleTime)
        if await isPlaying() {
            MusicLog.logger.info("Musik: \(appURL.absoluteString, privacy: .public) geöffnet und spielt.")
        } else {
            MusicLog.logger.notice("Musik: \(appURL.absoluteString, privacy: .public) geöffnet – Katalog-Links lassen sich per AppleScript nicht abspielen, bitte dort starten.")
        }
    }

    /// `https://music.apple.com/…` → `music://music.apple.com/…`, damit der Link in der
    /// Musik-App landet und nicht im Browser.
    static func musicAppURL(for url: URL) -> URL {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components.scheme = "music"
        return components.url ?? url
    }
}

// MARK: - Skripte

private enum Scripts {
    static let launch = #"tell application "Music" to launch"#
    static let state = ScriptableApp.tell("Music", "return player state as string")
    static let pause = ScriptableApp.tell("Music", "pause")

    static func playPlaylist(_ name: String) -> String {
        ScriptableApp.tell("Music", #"play playlist "\#(ScriptableApp.escaped(name))""#)
    }
}
