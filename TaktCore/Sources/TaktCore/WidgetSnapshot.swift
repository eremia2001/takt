import Foundation
import GRDB

/// Laufender Timer samt Projekt.
public struct RunningState: Sendable, Hashable {
    public let project: Project
    public let entry: TimeEntry

    public init(project: Project, entry: TimeEntry) {
        self.project = project
        self.entry = entry
    }
}

/// Alles, was das Widget für einen Timeline-Eintrag braucht – in einer Leseabfrage ermittelt.
public struct WidgetSnapshot: Sendable, Hashable {
    public let running: RunningState?
    /// Höchstens 3 zuletzt genutzte Projekte, ohne das laufende.
    public let recent: [Project]
    /// Summe heute OHNE den laufenden Eintrag – das Widget addiert dessen Dauer live.
    public let todayCompleted: TimeInterval

    public init(running: RunningState?, recent: [Project], todayCompleted: TimeInterval) {
        self.running = running
        self.recent = recent
        self.todayCompleted = todayCompleted
    }

    public static let maxRecent = 3

    /// Beispieldaten für die Widget-Galerie und Vorschauen.
    public static let placeholder: WidgetSnapshot = {
        let now = Date.now
        let portal = Project(
            id: UUID(uuidString: "6E1F3B2A-0C4D-4E5F-8A9B-0C1D2E3F4A01")!,
            name: "Kundenportal",
            colorHex: ProjectPalette.colors[0],
            sortOrder: 0,
            createdAt: now
        )
        let website = Project(
            id: UUID(uuidString: "6E1F3B2A-0C4D-4E5F-8A9B-0C1D2E3F4A02")!,
            name: "Website",
            colorHex: ProjectPalette.colors[1],
            sortOrder: 1,
            createdAt: now
        )
        let garden = Project(
            id: UUID(uuidString: "6E1F3B2A-0C4D-4E5F-8A9B-0C1D2E3F4A03")!,
            name: "Garten",
            colorHex: ProjectPalette.colors[5],
            isBusiness: false,
            sortOrder: 2,
            createdAt: now
        )
        let entry = TimeEntry(
            id: UUID(uuidString: "6E1F3B2A-0C4D-4E5F-8A9B-0C1D2E3F4B01")!,
            projectId: portal.id,
            startedAt: now.addingTimeInterval(-(1 * 3600 + 12 * 60))
        )
        return WidgetSnapshot(
            running: RunningState(project: portal, entry: entry),
            recent: [website, garden],
            todayCompleted: 2 * 3600 + 35 * 60
        )
    }()
}

extension AppDatabase {
    /// Momentaufnahme für das Widget. „Heute“ ist der Kalendertag von `now` in `calendar`.
    public func widgetSnapshot(now: Date = .now, calendar: Calendar = .current) throws -> WidgetSnapshot {
        let today = calendar.dateInterval(of: .day, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 24 * 3600)

        return try writer.read { db in
            var running: RunningState?
            if let entry = try Self.activeEntry(db),
               let project = try Project.fetchOne(db, id: entry.projectId) {
                running = RunningState(project: project, entry: entry)
            }

            // Ein Platz mehr laden, falls das laufende Projekt darunter ist.
            let recent = try Self.recentProjects(db, limit: WidgetSnapshot.maxRecent + 1, now: now)
                .filter { $0.id != running?.project.id }
                .prefix(WidgetSnapshot.maxRecent)

            let todayCompleted = try Self.entries(db, in: today)
                .filter { !$0.isRunning }
                .reduce(0) { $0 + Self.clippedDuration($1, to: today, now: now) }

            return WidgetSnapshot(running: running, recent: Array(recent), todayCompleted: todayCompleted)
        }
    }
}
