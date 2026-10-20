import AppKit
import Foundation
import Observation
import os
import TaktCore

/// Steuert die Spotify-Desktop-App per Apple Events passend zum laufenden Timer.
///
/// Reagiert auf Zustandsübergänge im `TaktStore` (auch auf Starts/Stopps aus dem Widget).
/// Alle Skripte laufen nacheinander auf einem Hintergrund-Thread; die UI blockiert nie.
@MainActor
@Observable
final class MusicController {
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let runner = AppleScriptRunner()
    /// Zählt Aufträge hoch; ein laufender Auftrag bricht ab, sobald ein neuerer kommt
    /// (z. B. Stopp, während Spotify noch startet).
    @ObservationIgnored private var generation = 0
    /// Zuletzt von Takt gestartete URI. Spotify verrät per AppleScript nur den aktuellen Titel,
    /// nicht die Playlist – daher merken wir uns, was wir selbst gestartet haben.
    @ObservationIgnored private var lastStartedURI: String?

    private static let logger = Logger(subsystem: "dev.eremiya.takt", category: "music")
    private static let spotifyBundleID = "com.spotify.client"
    /// Nach dem Start von Spotify: so oft (im Sekundenabstand) versuchen, die Playlist zu starten.
    private static let launchAttempts = 8

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: Öffentliche Schnittstelle

    /// Vom Store aufgerufen, wenn sich der laufende Eintrag geändert hat (nil→X, X→nil, X→Y).
    func timerDidChange(from old: RunningState?, to new: RunningState?) {
        guard settings.musicEnabled else { return }

        if let new {
            guard let uri = Self.nonEmpty(new.project.playlistURI) ?? Self.nonEmpty(settings.defaultPlaylistURI) else {
                Self.logger.debug("Keine Playlist für „\(new.project.name, privacy: .public)“ – Musik bleibt unverändert.")
                return
            }
            let job = nextGeneration()
            let takeOver = settings.takeOverPlayingMusic
            Task { await self.play(uri: uri, takeOver: takeOver, job: job) }
        } else if old != nil, settings.pauseOnStop {
            let job = nextGeneration()
            Task { await self.pauseIfPlaying(job: job, reason: "Timer gestoppt") }
        }
    }

    /// Pausiert Spotify für die Pausenerinnerung, falls gerade Musik läuft.
    func pauseForBreak() {
        guard settings.musicEnabled else { return }
        let job = nextGeneration()
        Task { await self.pauseIfPlaying(job: job, reason: "Pausenerinnerung") }
    }

    // MARK: Abläufe

    private func play(uri: String, takeOver: Bool, job: Int) async {
        guard isSpotifyRunning else {
            await launchAndPlay(uri: uri, job: job)
            return
        }

        if let status = await playerStatus(), status.state == "playing" {
            guard job == generation else { return }
            // Gleicher Kontext läuft schon: nichts tun, damit die Musik nicht neu beginnt.
            if status.trackURL == uri || lastStartedURI == uri {
                Self.logger.info("Spotify spielt bereits \(uri, privacy: .public).")
                return
            }
            if !takeOver {
                Self.logger.info("Spotify spielt bereits etwas anderes; Übernehmen ist ausgeschaltet.")
                return
            }
        }
        guard job == generation else { return }

        if case .failure(let error) = await runner.run(Scripts.play(uri)) {
            Self.logger.error("Abspielen von \(uri, privacy: .public) fehlgeschlagen: \(error.description, privacy: .public)")
            return
        }
        lastStartedURI = uri
        Self.logger.info("Spotify spielt \(uri, privacy: .public).")
    }

    /// Startet Spotify und versucht danach bis zu ~8 s lang, die Playlist abzuspielen.
    private func launchAndPlay(uri: String, job: Int) async {
        Self.logger.info("Spotify läuft nicht – wird gestartet.")
        if case .failure(let error) = await runner.run(Scripts.launch) {
            Self.logger.error("Spotify konnte nicht gestartet werden: \(error.description, privacy: .public)")
            return
        }

        for attempt in 1...Self.launchAttempts {
            try? await Task.sleep(for: .seconds(1))
            guard job == generation else { return }

            switch await runner.run(Scripts.play(uri)) {
            case .success:
                // Direkt nach dem Start nimmt Spotify Befehle teils an, ohne zu spielen – prüfen.
                try? await Task.sleep(for: .milliseconds(700))
                if let status = await playerStatus(), status.state == "playing" {
                    lastStartedURI = uri
                    Self.logger.info("Spotify spielt \(uri, privacy: .public) (Versuch \(attempt)).")
                    return
                }
            case .failure(let error):
                if error.isPermissionDenied {
                    Self.logger.error("Keine Erlaubnis, Spotify zu steuern: \(error.description, privacy: .public)")
                    return
                }
                Self.logger.debug("Versuch \(attempt): \(error.description, privacy: .public)")
            }
        }
        Self.logger.error("Spotify hat \(uri, privacy: .public) nach dem Start nicht abgespielt.")
    }

    private func pauseIfPlaying(job: Int, reason: String) async {
        // Spotify nicht starten, nur um zu pausieren.
        guard isSpotifyRunning else { return }
        guard let status = await playerStatus(), status.state == "playing", job == generation else { return }
        if case .failure(let error) = await runner.run(Scripts.pause) {
            Self.logger.error("Pausieren fehlgeschlagen: \(error.description, privacy: .public)")
            return
        }
        Self.logger.info("Spotify pausiert (\(reason, privacy: .public)).")
    }

    // MARK: Hilfen

    private func nextGeneration() -> Int {
        generation += 1
        return generation
    }

    /// Prüft ohne Apple Event, ob Spotify läuft (ein `tell` würde es sonst starten).
    private var isSpotifyRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == Self.spotifyBundleID && !$0.isTerminated
        }
    }

    private struct PlayerStatus {
        /// `playing`, `paused` oder `stopped`.
        let state: String
        /// `spotify:track:…` des aktuellen Titels, falls vorhanden.
        let trackURL: String?
    }

    private func playerStatus() async -> PlayerStatus? {
        switch await runner.run(Scripts.status) {
        case .success(let output):
            let parts = (output ?? "").split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard let state = parts.first, !state.isEmpty else { return nil }
            let track = parts.count > 1 ? String(parts[1]) : ""
            return PlayerStatus(state: String(state), trackURL: track.isEmpty ? nil : track)
        case .failure(let error):
            Self.logger.error("Spotify-Status nicht lesbar: \(error.description, privacy: .public)")
            return nil
        }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

// MARK: - Skripte

private enum Scripts {
    /// Zeitlimit je Apple Event, damit ein hängendes Spotify die Warteschlange nicht minutenlang blockiert.
    private static let timeout = 15

    static let launch = #"tell application "Spotify" to launch"#

    static let status = """
        tell application "Spotify"
            with timeout of \(timeout) seconds
                set playerState to player state as string
                set trackURL to ""
                try
                    set trackURL to spotify url of current track
                end try
                return playerState & "|" & trackURL
            end timeout
        end tell
        """

    static let pause = """
        tell application "Spotify"
            with timeout of \(timeout) seconds
                pause
            end timeout
        end tell
        """

    /// `spotify:playlist:…`, `spotify:album:…` und `spotify:track:…` gehen direkt per `play track`.
    static func play(_ uri: String) -> String {
        """
        tell application "Spotify"
            with timeout of \(timeout) seconds
                play track "\(escaped(uri))"
            end timeout
        end tell
        """
    }

    /// Maskiert Zeichen, die ein AppleScript-Zeichenkettenliteral beenden würden.
    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// MARK: - AppleScript-Ausführung

/// Fehler eines AppleScripts mit Nummer und Meldung aus `NSAppleScript`.
struct AppleScriptError: Error, Sendable, CustomStringConvertible {
    let code: Int
    let message: String

    /// -1743: Der Nutzer hat die Automation (Takt → Spotify) abgelehnt.
    var isPermissionDenied: Bool { code == -1743 }

    var description: String { "\(message) (\(code))" }
}

/// Führt `NSAppleScript` in-process auf einer seriellen Hintergrund-Warteschlange aus.
/// `NSAppleScript` ist nicht threadsicher; die serielle Warteschlange stellt sicher,
/// dass nie zwei Skripte gleichzeitig laufen.
final class AppleScriptRunner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.eremiya.takt.applescript", qos: .userInitiated)

    func run(_ source: String) async -> Result<String?, AppleScriptError> {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.execute(source))
            }
        }
    }

    private static func execute(_ source: String) -> Result<String?, AppleScriptError> {
        guard let script = NSAppleScript(source: source) else {
            return .failure(AppleScriptError(code: 0, message: "Skript konnte nicht angelegt werden"))
        }
        var errorInfo: NSDictionary?
        let output = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unbekannter Fehler"
            return .failure(AppleScriptError(code: code, message: message))
        }
        return .success(output.stringValue)
    }
}
