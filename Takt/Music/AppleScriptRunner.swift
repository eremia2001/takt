import Foundation

/// Fehler eines AppleScripts mit Nummer und Meldung aus `NSAppleScript`.
struct AppleScriptError: Error, Sendable, CustomStringConvertible {
    let code: Int
    let message: String

    /// -1743: Der Nutzer hat die Automation (Takt → Spotify/Musik) abgelehnt.
    var isPermissionDenied: Bool { code == -1743 }
    /// -1700/-1728: Objekt (z. B. Playlist) nicht gefunden bzw. nicht umwandelbar.
    var isObjectNotFound: Bool { code == -1700 || code == -1728 }

    var description: String { "\(message) (\(code))" }
}

/// Führt `NSAppleScript` in-process auf einer seriellen Hintergrund-Warteschlange aus.
/// `NSAppleScript` ist nicht threadsicher; die serielle Warteschlange stellt sicher,
/// dass nie zwei Skripte gleichzeitig laufen (auch nicht für verschiedene Apps).
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
