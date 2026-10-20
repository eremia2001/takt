import Foundation
import OSLog
import TaktCore

/// Datenbankzugang der Widget-Extension.
///
/// Bewusst nicht `AppDatabase.shared`: das endet mit `fatalError`, wenn sich die Datei nicht
/// öffnen lässt – das Widget soll in diesem Fall nur „Nichts läuft“ zeigen. Geöffnet wird
/// dieselbe Datei (`AppDatabase.defaultURL()`); ein Fehlschlag wird beim nächsten Aufruf erneut
/// versucht.
enum WidgetDatabase {
    private static let logger = Logger(subsystem: "dev.eremiya.takt.widget", category: "database")
    private static let lock = NSLock()
    private static var cached: AppDatabase?

    static func open() -> AppDatabase? {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let url = AppDatabase.defaultURL()
        do {
            let database = try AppDatabase.onDisk(at: url)
            cached = database
            logger.info("Datenbank geöffnet: \(url.path, privacy: .public)")
            return database
        } catch {
            // Sichtbar machen, warum das Widget leer bleibt (Sandbox, Pfad, Migration …).
            logger.error("Datenbank \(url.path, privacy: .public) nicht geöffnet: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
