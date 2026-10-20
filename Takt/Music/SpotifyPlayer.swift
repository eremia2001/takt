import Foundation
import TaktCore

/// Steuert die Spotify-Desktop-App per Apple Events.
@MainActor
final class SpotifyPlayer: MusicPlayer {
    let provider: MusicProvider = .spotify
    let canReadState = true

    private let runner: AppleScriptRunner
    private static let bundleID = "com.spotify.client"
    /// Nach dem Start von Spotify: so oft (im Sekundenabstand) versuchen, die Playlist zu starten.
    private static let launchAttempts = 8

    init(runner: AppleScriptRunner) {
        self.runner = runner
    }

    var isRunning: Bool { ScriptableApp.isRunning(bundleID: Self.bundleID) }

    func play(_ source: MusicSource) async throws {
        guard case .spotify(let uri) = source else { throw MusicPlayerError.unsupportedSource(source) }
        guard isRunning else {
            try await launchAndPlay(uri: uri)
            return
        }

        // Gleicher Titel läuft schon: nichts tun, damit die Musik nicht neu beginnt.
        if let status = await status(), status.state == "playing", status.trackURL == uri {
            MusicLog.logger.info("Spotify spielt bereits \(uri, privacy: .public).")
            return
        }
        try Task.checkCancellation()

        if case .failure(let error) = await runner.run(Scripts.play(uri)) {
            throw MusicPlayerError.script(error)
        }
        MusicLog.logger.info("Spotify spielt \(uri, privacy: .public).")
    }

    func pause() async {
        // Spotify nicht starten, nur um zu pausieren.
        guard isRunning else { return }
        guard let status = await status(), status.state == "playing", !Task.isCancelled else { return }
        if case .failure(let error) = await runner.run(Scripts.pause) {
            MusicLog.logger.error("Spotify: Pausieren fehlgeschlagen: \(error.description, privacy: .public)")
            return
        }
        MusicLog.logger.info("Spotify pausiert.")
    }

    func isPlaying() async -> Bool {
        guard isRunning else { return false }
        return await status()?.state == "playing"
    }

    // MARK: Abläufe

    /// Startet Spotify und versucht danach bis zu ~8 s lang, die Playlist abzuspielen.
    private func launchAndPlay(uri: String) async throws {
        MusicLog.logger.info("Spotify läuft nicht – wird gestartet.")
        if case .failure(let error) = await runner.run(Scripts.launch) {
            throw MusicPlayerError.script(error)
        }

        for attempt in 1...Self.launchAttempts {
            try await Task.sleep(for: .seconds(1))

            switch await runner.run(Scripts.play(uri)) {
            case .success:
                // Direkt nach dem Start nimmt Spotify Befehle teils an, ohne zu spielen – prüfen.
                try await Task.sleep(for: .milliseconds(700))
                if let status = await status(), status.state == "playing" {
                    MusicLog.logger.info("Spotify spielt \(uri, privacy: .public) (Versuch \(attempt)).")
                    return
                }
            case .failure(let error):
                if error.isPermissionDenied { throw MusicPlayerError.script(error) }
                MusicLog.logger.debug("Spotify, Versuch \(attempt): \(error.description, privacy: .public)")
            }
        }
        throw MusicPlayerError.notPlaying("Spotify hat \(uri) nach dem Start nicht abgespielt.")
    }

    // MARK: Zustand

    private struct Status {
        /// `playing`, `paused` oder `stopped`.
        let state: String
        /// `spotify:track:…` des aktuellen Titels, falls vorhanden.
        let trackURL: String?
    }

    private func status() async -> Status? {
        switch await runner.run(Scripts.status) {
        case .success(let output):
            let parts = (output ?? "").split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard let state = parts.first, !state.isEmpty else { return nil }
            let track = parts.count > 1 ? String(parts[1]) : ""
            return Status(state: String(state), trackURL: track.isEmpty ? nil : track)
        case .failure(let error):
            MusicLog.logger.error("Spotify-Status nicht lesbar: \(error.description, privacy: .public)")
            return nil
        }
    }
}

// MARK: - Skripte

private enum Scripts {
    static let launch = #"tell application "Spotify" to launch"#

    static let status = ScriptableApp.tell("Spotify", """
        set playerState to player state as string
                set trackURL to ""
                try
                    set trackURL to spotify url of current track
                end try
                return playerState & "|" & trackURL
        """)

    static let pause = ScriptableApp.tell("Spotify", "pause")

    /// `spotify:playlist:…`, `spotify:album:…` und `spotify:track:…` gehen direkt per `play track`.
    static func play(_ uri: String) -> String {
        ScriptableApp.tell("Spotify", #"play track "\#(ScriptableApp.escaped(uri))""#)
    }
}
