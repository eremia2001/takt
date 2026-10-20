import AppKit
import ApplicationServices
import Foundation
import TaktCore

/// Öffnet Web-Links (YouTube, YouTube Music, …) im Standardbrowser.
///
/// Grenzen: Was im Browser läuft, lässt sich nicht auslesen (`isPlaying()` ist immer `false`).
/// Pausiert wird – falls eingeschaltet – mit der Medientaste Play/Pause. Die wirkt auf die
/// App unter „Aktuell läuft“ und *schaltet um*: War dort schon pausiert, startet sie wieder.
@MainActor
final class BrowserPlayer: MusicPlayer {
    let provider: MusicProvider = .browser
    let canReadState = false

    /// Liest die Einstellung „Browser: beim Stoppen Medientaste senden“ zum Zeitpunkt der Pause.
    private let sendsMediaKey: () -> Bool
    /// Zuletzt geöffneter Link; bestimmt, welche App als „der Browser“ gilt.
    private var lastOpenedURL: URL?

    init(sendsMediaKey: @escaping () -> Bool) {
        self.sendsMediaKey = sendsMediaKey
    }

    /// Läuft die App, die den zuletzt geöffneten Link (sonst `https`) öffnet?
    var isRunning: Bool {
        guard let fallback = URL(string: "https://www.youtube.com"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: lastOpenedURL ?? fallback),
              let bundleID = Bundle(url: appURL)?.bundleIdentifier
        else { return false }
        return ScriptableApp.isRunning(bundleID: bundleID)
    }

    func play(_ source: MusicSource) async throws {
        guard case .web(let url) = source else { throw MusicPlayerError.unsupportedSource(source) }
        try Task.checkCancellation()

        let configuration = NSWorkspace.OpenConfiguration()
        // Im Vordergrund öffnen: Browser verzögern Medien in Hintergrund-Tabs oft bis zur Anzeige.
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.open(url, configuration: configuration)
        } catch {
            throw MusicPlayerError.openFailed(url, error.localizedDescription)
        }
        lastOpenedURL = url
        MusicLog.logger.info("Browser: \(url.absoluteString, privacy: .public) geöffnet.")
    }

    func pause() async {
        guard sendsMediaKey() else {
            MusicLog.logger.debug("Browser: Medientaste ist ausgeschaltet – keine Pause.")
            return
        }
        // Ohne laufenden Browser würde die Medientaste ggf. die Musik-App starten.
        guard isRunning else {
            MusicLog.logger.info("Browser läuft nicht mehr – keine Medientaste.")
            return
        }
        guard !Task.isCancelled else { return }
        guard AXIsProcessTrusted() else {
            MusicLog.logger.error("Browser: Medientaste braucht die Berechtigung „Bedienungshilfen“ für Takt.")
            return
        }
        MediaKey.sendPlayPause()
        MusicLog.logger.info("Browser: Medientaste Play/Pause gesendet.")
    }

    /// Im Browser nicht ermittelbar.
    func isPlaying() async -> Bool { false }
}

/// Simuliert die Medientaste Play/Pause der Tastatur.
enum MediaKey {
    /// `NX_KEYTYPE_PLAY` aus `IOKit/hidsystem/ev_keymap.h`.
    private static let playKeyType = 16
    /// `NX_SUBTYPE_AUX_CONTROL_BUTTONS`.
    private static let auxControlSubtype: Int16 = 8

    /// Sendet Taste-runter und Taste-hoch. Ohne Berechtigung „Bedienungshilfen“
    /// verwirft macOS die Ereignisse stillschweigend.
    static func sendPlayPause() {
        for isDown in [true, false] {
            let state = isDown ? 0xA : 0xB
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: auxControlSubtype,
                data1: (playKeyType << 16) | (state << 8),
                data2: -1
            ) else { continue }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// Ob Takt Tastenereignisse senden darf; `prompt` zeigt die Systemabfrage.
    static func isAllowed(prompt: Bool = false) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
