import AppKit
import Foundation
import os
import TaktCore

/// Ein Anbieter, der Musik zum Timer abspielen und pausieren kann.
///
/// Abbruch: Läuft ein Auftrag noch (z. B. Spotify startet gerade), bricht `MusicController`
/// die zugehörige `Task` ab; Implementierungen prüfen das zwischen ihren Schritten
/// (`Task.checkCancellation()`, `Task.sleep` wirft bei Abbruch).
@MainActor
protocol MusicPlayer: AnyObject {
    /// Wofür der Player zuständig ist.
    var provider: MusicProvider { get }
    /// Läuft die zugehörige App? Prüft ohne Apple Event (ein `tell` würde sie starten).
    var isRunning: Bool { get }
    /// Ob `isPlaying()` den echten Zustand kennt. Im Browser nicht ermittelbar.
    var canReadState: Bool { get }

    /// Spielt die Quelle ab; startet die App bei Bedarf.
    func play(_ source: MusicSource) async throws
    /// Pausiert, falls gerade etwas läuft. Startet die App nie, nur um zu pausieren.
    func pause() async
    /// Ob gerade Musik läuft (`false`, wenn unbekannt).
    func isPlaying() async -> Bool
}

/// Fehler beim Abspielen; landen im Log, nie in der Oberfläche.
enum MusicPlayerError: Error, CustomStringConvertible {
    /// Quelle passt nicht zum Player (Programmierfehler).
    case unsupportedSource(MusicSource)
    /// AppleScript ist fehlgeschlagen.
    case script(AppleScriptError)
    /// App ließ sich nicht starten oder hat nach dem Start nicht abgespielt.
    case notPlaying(String)
    /// Link ließ sich nicht öffnen.
    case openFailed(URL, String)

    var description: String {
        switch self {
        case .unsupportedSource(let source): "Quelle passt nicht zum Player: \(source.storageString)"
        case .script(let error): error.description
        case .notPlaying(let message): message
        case .openFailed(let url, let message): "\(url.absoluteString) nicht geöffnet: \(message)"
        }
    }
}

/// Gemeinsames Log der Musiksteuerung.
enum MusicLog {
    static let logger = Logger(subsystem: "dev.eremiya.takt", category: "music")
}

/// Hilfen für Apps, die per AppleScript gesteuert werden (Spotify, Musik).
enum ScriptableApp {
    /// Zeitlimit je Apple Event, damit eine hängende App die Warteschlange nicht minutenlang blockiert.
    static let timeout = 15

    /// Prüft ohne Apple Event, ob die App läuft.
    static func isRunning(bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleID && !$0.isTerminated
        }
    }

    /// Maskiert Zeichen, die ein AppleScript-Zeichenkettenliteral beenden würden.
    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Ein Befehl im `tell`-Block der App, mit Zeitlimit.
    static func tell(_ appName: String, _ body: String) -> String {
        """
        tell application "\(appName)"
            with timeout of \(timeout) seconds
                \(body)
            end timeout
        end tell
        """
    }
}
