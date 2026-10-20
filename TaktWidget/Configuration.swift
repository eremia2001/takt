import AppIntents
import Foundation
import TaktCore
import WidgetKit

// MARK: - Konfiguration pro Widget („Widget bearbeiten“)

/// Stil eines einzelnen Widgets. „Standard“ folgt der Einstellung in der App
/// (`SharedSettings.widgetStyle`), die übrigen Fälle legen den Stil fest.
enum WidgetStyleOption: String, AppEnum {
    case standard
    case plain
    case colorField
    case ring

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Stil"

    static var caseDisplayRepresentations: [WidgetStyleOption: DisplayRepresentation] = [
        .standard: "Standard",
        .plain: "Schlicht",
        .colorField: "Farbfläche",
        .ring: "Ring",
    ]

    /// Tatsächlicher Stil; „Standard“ wird bei jedem Laden der Timeline neu gelesen.
    var resolved: WidgetStyle {
        switch self {
        case .standard: SharedSettings.widgetStyle
        case .plain: .plain
        case .colorField: .colorField
        case .ring: .ring
        }
    }
}

/// Projekt als Auswahl in der Widget-Konfiguration.
struct ProjectEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Projekt"
    static var defaultQuery = ProjectEntityQuery()

    let id: UUID
    let name: String

    init(project: Project) {
        id = project.id
        name = project.name
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// Liefert die Projekte aus der gemeinsamen Datenbank. Vorgeschlagen werden nur aktive Projekte;
/// ein bereits gewähltes, inzwischen archiviertes Projekt wird aber weiter aufgelöst, damit das
/// Widget nicht stillschweigend auf „alle Projekte“ zurückfällt.
struct ProjectEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ProjectEntity] {
        guard let database = WidgetDatabase.open() else { return [] }
        let projects = (try? database.allProjects()) ?? []
        return identifiers.compactMap { id in
            projects.first { $0.id == id }.map(ProjectEntity.init(project:))
        }
    }

    func suggestedEntities() async throws -> [ProjectEntity] {
        guard let database = WidgetDatabase.open() else { return [] }
        return ((try? database.activeProjects()) ?? []).map(ProjectEntity.init(project:))
    }
}

/// Konfiguration eines Takt-Widgets: Stil und optional ein festes Projekt.
struct TaktWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Takt"
    static var description = IntentDescription(
        "Zeigt den laufenden Timer. Starten und Stoppen mit einem Klick. Stil und Projekt pro Widget wählbar."
    )

    @Parameter(title: "Stil", default: .standard)
    var style: WidgetStyleOption

    /// `nil` = alle Projekte.
    @Parameter(title: "Projekt", description: "Leer lassen für alle Projekte.")
    var project: ProjectEntity?

    init() {}

    init(style: WidgetStyleOption, project: ProjectEntity? = nil) {
        self.style = style
        self.project = project
    }
}
