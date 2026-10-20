import AppKit
import Foundation
import Observation
import os
import TaktCore

/// Steuert Musik passend zum laufenden Timer: Spotify, Apple Music (Musik-App) oder ein
/// Web-Link im Browser – je nach Quelle des Projekts.
///
/// Reagiert auf Zustandsübergänge im `TaktStore` (auch auf Starts/Stopps aus dem Widget).
/// Aufträge laufen nacheinander; ein neuer Auftrag bricht den laufenden ab (z. B. Stopp,
/// während Spotify noch startet). AppleScripts laufen auf einem Hintergrund-Thread,
/// die UI blockiert nie.
@MainActor
@Observable
final class MusicController {
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let spotify: SpotifyPlayer
    @ObservationIgnored private let appleMusic: AppleMusicPlayer
    @ObservationIgnored private let browser: BrowserPlayer

    /// Laufender Auftrag; wird beim nächsten abgebrochen, der nächste wartet auf sein Ende.
    @ObservationIgnored private var currentTask: Task<Void, Never>?
    /// Anbieter, der zuletzt gestartet hat (oder dessen laufende Musik übernommen wurde).
    /// Ihn pausieren Stopp und Pausenerinnerung.
    @ObservationIgnored private var activeProvider: MusicProvider?
    /// Zuletzt von Takt gestartete Quelle. Spotify verrät per AppleScript nur den aktuellen
    /// Titel, nicht die Playlist – daher merken wir uns, was wir selbst gestartet haben.
    /// Bei Browser-Quellen wird sie nach einer Pause gelöscht (dann ist nichts mehr „offen“).
    @ObservationIgnored private var lastStarted: MusicSource?

    private static let logger = MusicLog.logger

    init(settings: AppSettings) {
        self.settings = settings
        let runner = AppleScriptRunner()
        spotify = SpotifyPlayer(runner: runner)
        appleMusic = AppleMusicPlayer(runner: runner)
        browser = BrowserPlayer(sendsMediaKey: { [settings] in settings.browserPauseWithMediaKey })
    }

    // MARK: Öffentliche Schnittstelle

    /// Vom Store aufgerufen, wenn sich der laufende Eintrag geändert hat (nil→X, X→nil, X→Y).
    func timerDidChange(from old: RunningState?, to new: RunningState?) {
        guard isEnabled else { return }

        if let new {
            guard let source = source(for: new.project) else {
                Self.logger.debug("Keine Musikquelle für „\(new.project.name, privacy: .public)“ – Musik bleibt unverändert.")
                return
            }
            let takeOver = settings.takeOverPlayingMusic
            enqueue { try await self.start(source, takeOver: takeOver) }
        } else if old != nil, settings.pauseOnStop {
            enqueue { await self.pauseActive(reason: "Timer gestoppt") }
        }
    }

    /// Pausiert den zuletzt aktiven Player für die Pausenerinnerung, falls gerade Musik läuft.
    func pauseForBreak() {
        guard isEnabled else { return }
        enqueue { await self.pauseActive(reason: "Pausenerinnerung") }
    }

    // MARK: Auswahl

    /// „Keine“ als bevorzugter Anbieter schaltet die Steuerung ab, wie der globale Schalter.
    private var isEnabled: Bool { settings.musicEnabled && settings.musicProvider != .none }

    /// Quelle des Projekts, sonst die Standard-Quelle aus den Einstellungen.
    /// Der bevorzugte Anbieter entscheidet bei mehrdeutigem Text (bloßer Name → Apple-Music-Playlist).
    private func source(for project: Project) -> MusicSource? {
        let preferred = settings.musicProvider
        if let text = project.musicSource, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let source = MusicSource.parse(text, preferring: preferred) { return source }
            Self.logger.error("Musikquelle von „\(project.name, privacy: .public)“ nicht erkannt: \(text, privacy: .public) – nehme Standard-Quelle.")
        }
        guard let text = settings.defaultPlaylistURI else { return nil }
        let source = MusicSource.parse(text, preferring: preferred)
        if source == nil {
            Self.logger.error("Standard-Quelle nicht erkannt: \(text, privacy: .public)")
        }
        return source
    }

    private func player(for provider: MusicProvider) -> (any MusicPlayer)? {
        switch provider {
        case .spotify: spotify
        case .appleMusic: appleMusic
        case .browser: browser
        case .none: nil
        }
    }

    // MARK: Abläufe

    /// Bricht den laufenden Auftrag ab und reiht `work` dahinter ein.
    private func enqueue(_ work: @escaping @MainActor () async throws -> Void) {
        let previous = currentTask
        previous?.cancel()
        currentTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            do {
                try await work()
            } catch is CancellationError {
                // Neuerer Auftrag hat übernommen.
            } catch {
                Self.logger.error("Musik: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func start(_ source: MusicSource, takeOver: Bool) async throws {
        guard let player = player(for: source.provider) else { return }

        // Anbieterwechsel (z. B. Spotify → Browser): den bisherigen anhalten.
        if let active = activeProvider, active != source.provider {
            await pause(active, reason: "Anbieterwechsel")
            activeProvider = nil
        }
        try Task.checkCancellation()

        if player.canReadState {
            if player.isRunning, await player.isPlaying() {
                try Task.checkCancellation()
                // Gleiche Quelle läuft schon: nichts tun, damit die Musik nicht neu beginnt.
                if lastStarted == source {
                    Self.logger.info("\(source.provider.title, privacy: .public) spielt bereits \(source.storageString, privacy: .public).")
                    activeProvider = source.provider
                    return
                }
                if !takeOver {
                    Self.logger.info("\(source.provider.title, privacy: .public) spielt bereits etwas anderes; Übernehmen ist ausgeschaltet.")
                    activeProvider = source.provider
                    return
                }
            }
        } else if lastStarted == source, activeProvider == source.provider {
            // Browser: Zustand nicht lesbar. Gleicher Link ist geöffnet und wurde nicht pausiert
            // (Projektwechsel mit gleicher Quelle) – keinen zweiten Tab öffnen.
            Self.logger.info("Browser: \(source.storageString, privacy: .public) ist bereits geöffnet.")
            return
        }
        try Task.checkCancellation()

        try await player.play(source)
        lastStarted = source
        activeProvider = source.provider
    }

    /// Pausiert den zuletzt aktiven Player. Hat Takt in dieser Sitzung noch nichts gestartet,
    /// den bevorzugten Anbieter – außer dem Browser, dort würde die Medientaste blind umschalten.
    private func pauseActive(reason: String) async {
        let fallback: MusicProvider? = switch settings.musicProvider {
        case .spotify, .appleMusic: settings.musicProvider
        case .browser, .none: nil
        }
        guard let provider = activeProvider ?? fallback else { return }
        await pause(provider, reason: reason)
    }

    private func pause(_ provider: MusicProvider, reason: String) async {
        guard let player = player(for: provider) else { return }
        Self.logger.debug("\(provider.title, privacy: .public) pausieren (\(reason, privacy: .public)).")

        if provider == .browser {
            // Medientaste nur, wenn Takt den Link geöffnet und seitdem nicht schon pausiert hat –
            // sonst würde sie die Wiedergabe wieder starten.
            guard lastStarted?.provider == .browser else {
                Self.logger.debug("Browser: nichts von Takt Geöffnetes zu pausieren.")
                return
            }
            await player.pause()
            lastStarted = nil
            return
        }
        await player.pause()
    }
}
