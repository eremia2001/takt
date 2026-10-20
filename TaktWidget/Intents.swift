import AppIntents
import Foundation
import TaktCore

/// Startet den Timer für ein Projekt (Schnellstart-Zeilen im Widget).
struct StartTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Timer starten"
    static var description = IntentDescription("Startet den Timer für ein Projekt.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Projekt")
    var projectID: String

    init() {}

    init(projectID: String) {
        self.projectID = projectID
    }

    func perform() async throws -> some IntentResult {
        // Fehler werden geschluckt: ein Klick im Widget darf nie zum Absturz führen.
        guard let id = UUID(uuidString: projectID), let database = WidgetDatabase.open() else {
            return .result()
        }
        do {
            try database.startTimer(projectId: id)
            ChangeNotifier.post()
        } catch {}
        return .result()
    }
}

/// Stoppt den laufenden Timer (Stopp-Knopf im Widget).
struct StopTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Timer stoppen"
    static var description = IntentDescription("Stoppt den laufenden Timer.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        guard let database = WidgetDatabase.open() else { return .result() }
        do {
            try database.stopTimer()
            ChangeNotifier.post()
        } catch {}
        return .result()
    }
}

/// Entfernt den geplanten Block (×-Knopf im großen Widget).
struct ClearPlannedBlockIntent: AppIntent {
    static var title: LocalizedStringResource = "Geplanten Block entfernen"
    static var description = IntentDescription("Entfernt den geplanten nächsten Block.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        guard let database = WidgetDatabase.open() else { return .result() }
        do {
            try database.clearPlannedBlock()
            ChangeNotifier.post()
        } catch {}
        return .result()
    }
}
