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
///
/// Dauern sind auf den Zeitpunkt der Momentaufnahme bezogen. Für die minütliche Anzeige
/// rechnet das Widget die Dauer des laufenden Eintrags selbst dazu (siehe `todayCompleted`,
/// `BudgetInfo.used(at:runningSince:)`).
public struct WidgetSnapshot: Sendable, Hashable {
    // MARK: Bausteine

    /// Ein heutiger Eintrag für die Tagesleiste, auf den Kalendertag zugeschnitten.
    public struct TodayEntry: Sendable, Hashable {
        public let projectId: UUID
        /// Projektfarbe als `#RRGGBB`.
        public let colorHex: String
        /// Beginn, frühestens Mitternacht des Tages.
        public let startedAt: Date
        /// Ende, spätestens Mitternacht des Folgetages; `nil` = läuft.
        public let endedAt: Date?

        public init(projectId: UUID, colorHex: String, startedAt: Date, endedAt: Date?) {
            self.projectId = projectId
            self.colorHex = colorHex
            self.startedAt = startedAt
            self.endedAt = endedAt
        }

        public var isRunning: Bool { endedAt == nil }
    }

    /// Der geplante „nächste Block“ samt Projekt.
    public struct PlannedBlockInfo: Sendable, Hashable {
        public let project: Project
        public let startAt: Date
        public let note: String?

        public init(project: Project, startAt: Date, note: String?) {
            self.project = project
            self.startAt = startAt
            self.note = note
        }

        /// Beginn erreicht (ab hier „jetzt starten“ statt „um 14:00“).
        public func isDue(at date: Date) -> Bool { startAt <= date }
    }

    /// Stundenbudget eines Projekts und der Verbrauch über alle Einträge (nicht nur heute).
    public struct BudgetInfo: Sendable, Hashable {
        /// Verbraucht zum Zeitpunkt der Momentaufnahme, laufender Eintrag bis dahin eingeschlossen.
        public let used: TimeInterval
        /// Budget in Sekunden, immer > 0.
        public let budget: TimeInterval
        /// Davon in abgeschlossenen Einträgen (ohne den laufenden) – Grundlage für die Live-Anzeige.
        public let completed: TimeInterval

        public init(used: TimeInterval, budget: TimeInterval, completed: TimeInterval? = nil) {
            self.used = used
            self.budget = budget
            self.completed = completed ?? used
        }

        /// Anteil verbraucht (1 = Budget erreicht, darüber = überzogen).
        public var fraction: Double { budget > 0 ? used / budget : 0 }

        /// Verbrauch zu einem späteren Zeitpunkt: abgeschlossene Zeit plus die laufende Dauer
        /// seit `runningSince` (`nil`, wenn das Projekt nicht läuft).
        public func used(at date: Date, runningSince: Date?) -> TimeInterval {
            guard let runningSince else { return completed }
            return completed + max(0, date.timeIntervalSince(runningSince))
        }

        public func fraction(at date: Date, runningSince: Date?) -> Double {
            budget > 0 ? used(at: date, runningSince: runningSince) / budget : 0
        }
    }

    // MARK: Felder

    /// Laufender Timer. Im Ein-Projekt-Widget nur, wenn dieses Projekt läuft.
    public let running: RunningState?
    /// Höchstens 3 zuletzt genutzte Projekte, ohne das laufende.
    public let recent: [Project]
    /// Höchstens 2 zuletzt genutzte andere Projekte für „Wechseln“ im Lauf-Zustand
    /// (ohne das laufende). Läuft nichts, die ersten zwei aus `recent`.
    public let switchTargets: [Project]
    /// Alle aktiven Projekte nach `sortOrder` (großes Widget), das laufende eingeschlossen.
    public let allProjects: [Project]
    /// Summe heute OHNE den laufenden Eintrag – das Widget addiert dessen Dauer live.
    public let todayCompleted: TimeInterval
    /// Heutige Einträge aller Projekte (Kalendertag), nach Beginn sortiert, laufender eingeschlossen.
    public let todayEntries: [TodayEntry]
    /// „Nächster Schritt“ vom vorherigen Lauf des laufenden Projekts.
    public let runningNextStep: String?
    /// Der geplante nächste Block (fällige bis 4 h nach Beginn).
    public let plannedBlock: PlannedBlockInfo?
    /// Minuten bis zur Pausenerinnerung, `nil` wenn die Erinnerung aus ist.
    public let breakReminderMinutes: Int?
    /// Budget des laufenden Projekts, nur wenn es eines hat. Im Ein-Projekt-Widget das Budget
    /// dieses Projekts – auch, wenn es gerade nicht läuft.
    public let runningBudget: BudgetInfo?
    /// Ein-Projekt-Widget: das feste Projekt; sonst `nil`.
    public let fixedProjectID: UUID?
    /// Ein-Projekt-Widget: ein anderes Projekt läuft gerade (dann ist `running` `nil`).
    public let fixedProjectRunningElsewhere: Bool
    /// Pomodoro-Zustand aus `SharedSettings`, nur bei eingeschaltetem Modus.
    public let pomodoro: PomodoroState?

    public init(
        running: RunningState?,
        recent: [Project],
        todayCompleted: TimeInterval,
        switchTargets: [Project]? = nil,
        allProjects: [Project] = [],
        todayEntries: [TodayEntry] = [],
        runningNextStep: String? = nil,
        plannedBlock: PlannedBlockInfo? = nil,
        breakReminderMinutes: Int? = nil,
        runningBudget: BudgetInfo? = nil,
        fixedProjectID: UUID? = nil,
        fixedProjectRunningElsewhere: Bool = false,
        pomodoro: PomodoroState? = nil
    ) {
        self.running = running
        self.recent = recent
        self.todayCompleted = todayCompleted
        self.switchTargets = switchTargets ?? Array(recent.prefix(Self.maxSwitchTargets))
        self.allProjects = allProjects
        self.todayEntries = todayEntries
        self.runningNextStep = runningNextStep
        self.plannedBlock = plannedBlock
        self.breakReminderMinutes = breakReminderMinutes
        self.runningBudget = runningBudget
        self.fixedProjectID = fixedProjectID
        self.fixedProjectRunningElsewhere = fixedProjectRunningElsewhere
        self.pomodoro = pomodoro
    }

    public static let maxRecent = 3
    public static let maxSwitchTargets = 2

    // MARK: Beispieldaten

    /// Beispieldaten für die Widget-Galerie und Vorschauen: „Kundenportal“ läuft seit 1:12
    /// (Budget 12:30 von 40 h), geplant ist „Website“ zur übernächsten Viertelstunde,
    /// Pomodoro in Einheit 2 von 4 mit 23 Minuten Rest.
    public static let placeholder: WidgetSnapshot = {
        let now = Date.now
        let portal = Project(
            id: UUID(uuidString: "6E1F3B2A-0C4D-4E5F-8A9B-0C1D2E3F4A01")!,
            name: "Kundenportal",
            colorHex: ProjectPalette.colors[0],
            sortOrder: 0,
            budgetHours: 40,
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
        let runningSince = now.addingTimeInterval(-(1 * 3600 + 12 * 60))
        let entry = TimeEntry(
            id: UUID(uuidString: "6E1F3B2A-0C4D-4E5F-8A9B-0C1D2E3F4B01")!,
            projectId: portal.id,
            startedAt: runningSince
        )

        // Vorher: Website 2:00, dann Garten 0:35 – zusammen die 2:35 aus `todayCompleted`.
        let gardenEnd = runningSince.addingTimeInterval(-10 * 60)
        let gardenStart = gardenEnd.addingTimeInterval(-35 * 60)
        let websiteEnd = gardenStart.addingTimeInterval(-15 * 60)
        let websiteStart = websiteEnd.addingTimeInterval(-2 * 3600)
        let todayEntries = [
            TodayEntry(projectId: website.id, colorHex: website.colorHex, startedAt: websiteStart, endedAt: websiteEnd),
            TodayEntry(projectId: garden.id, colorHex: garden.colorHex, startedAt: gardenStart, endedAt: gardenEnd),
            TodayEntry(projectId: portal.id, colorHex: portal.colorHex, startedAt: runningSince, endedAt: nil),
        ]

        // Übernächste volle Viertelstunde (mindestens 15 Minuten entfernt).
        let quarter: TimeInterval = 15 * 60
        let plannedStart = Date(
            timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / quarter).rounded(.down) * quarter + 2 * quarter
        )

        let used: TimeInterval = 12 * 3600 + 30 * 60
        return WidgetSnapshot(
            running: RunningState(project: portal, entry: entry),
            recent: [website, garden],
            todayCompleted: 2 * 3600 + 35 * 60,
            switchTargets: [website, garden],
            allProjects: [portal, website, garden],
            todayEntries: todayEntries,
            runningNextStep: "Login-Fehler im Staging nachstellen",
            plannedBlock: PlannedBlockInfo(project: website, startAt: plannedStart, note: "Deploy vorbereiten"),
            breakReminderMinutes: SharedSettings.defaultBreakReminderMinutes,
            runningBudget: BudgetInfo(used: used, budget: 40 * 3600, completed: used - entry.duration(at: now)),
            pomodoro: PomodoroState(
                enabled: true,
                phase: .work,
                phaseEndsAt: now.addingTimeInterval(23 * 60),
                cycle: 2,
                cyclesBeforeLongBreak: 4,
                updatedAt: now
            )
        )
    }()
}

extension AppDatabase {
    /// Momentaufnahme für das Widget. „Heute“ ist der Kalendertag von `now` in `calendar`.
    ///
    /// - Parameters:
    ///   - fixedProjectID: Ein-Projekt-Widget. Dann enthalten `recent`, `switchTargets` und
    ///     `allProjects` nur dieses Projekt (gibt es es nicht: leer), `running` ist nur gesetzt,
    ///     wenn dieses Projekt läuft (sonst `fixedProjectRunningElsewhere`), und `todayCompleted`,
    ///     `runningBudget` und `plannedBlock` beziehen sich nur auf dieses Projekt.
    ///     `todayEntries` bleibt vollständig (enthält `projectId` zum Filtern).
    ///   - sharedDefaults: Suite, aus der Pausenerinnerung und Pomodoro-Zustand gelesen werden
    ///     (für Tests injizierbar).
    public func widgetSnapshot(
        now: Date = .now,
        calendar: Calendar = .current,
        fixedProjectID: UUID? = nil,
        sharedDefaults: UserDefaults = SharedSettings.defaults
    ) throws -> WidgetSnapshot {
        let today = calendar.dateInterval(of: .day, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 24 * 3600)
        let breakReminderMinutes = SharedSettings.breakReminderMinutesIfEnabled(in: sharedDefaults)
        let pomodoro = SharedSettings.pomodoroIfEnabled(in: sharedDefaults)

        return try writer.read { db in
            let projectsById = Dictionary(
                try Project.fetchAll(db).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            var globalRunning: RunningState?
            if let entry = try Self.activeEntry(db), let project = projectsById[entry.projectId] {
                globalRunning = RunningState(project: project, entry: entry)
            }

            // Laufender Timer und Projektlisten – im Ein-Projekt-Widget nur dieses Projekt.
            let running: RunningState?
            let runningElsewhere: Bool
            let recent: [Project]
            let switchTargets: [Project]
            let allProjects: [Project]
            if let fixedProjectID {
                running = globalRunning?.project.id == fixedProjectID ? globalRunning : nil
                runningElsewhere = globalRunning != nil && running == nil
                let only = projectsById[fixedProjectID].map { [$0] } ?? []
                allProjects = only
                recent = only.filter { $0.id != running?.project.id }
                switchTargets = recent
            } else {
                running = globalRunning
                runningElsewhere = false
                // Ein Platz mehr laden, falls das laufende Projekt darunter ist.
                let candidates = try Self.recentProjects(db, limit: WidgetSnapshot.maxRecent + 1, now: now)
                    .filter { $0.id != running?.project.id }
                recent = Array(candidates.prefix(WidgetSnapshot.maxRecent))
                switchTargets = Array(candidates.prefix(WidgetSnapshot.maxSwitchTargets))
                allProjects = try Project
                    .filter(Project.Columns.isArchived == false)
                    .order(Project.Columns.sortOrder, Project.Columns.name)
                    .fetchAll(db)
            }

            // Heute: Tagesleiste mit allen Projekten, Summe ggf. nur für das feste Projekt.
            let entries = try Self.entries(db, in: today)
            let todayEntries = entries.map { entry in
                let start = max(entry.startedAt, today.start)
                return WidgetSnapshot.TodayEntry(
                    projectId: entry.projectId,
                    colorHex: projectsById[entry.projectId]?.colorHex ?? ProjectPalette.colors[6],
                    startedAt: start,
                    endedAt: entry.endedAt.map { max(start, min($0, today.end)) }
                )
            }
            let todayCompleted = entries
                .filter { !$0.isRunning && (fixedProjectID == nil || $0.projectId == fixedProjectID) }
                .reduce(0) { $0 + Self.clippedDuration($1, to: today, now: now) }

            let runningNextStep = try running.flatMap { try Self.lastNextStep(db, projectId: $0.project.id) }

            // Geplanter Block: nur mit nicht archiviertem Projekt, im Ein-Projekt-Widget nur dessen.
            var plannedBlock: WidgetSnapshot.PlannedBlockInfo?
            if let block = try Self.plannedBlock(db, now: now),
               let project = projectsById[block.projectId], !project.isArchived,
               fixedProjectID == nil || block.projectId == fixedProjectID {
                plannedBlock = WidgetSnapshot.PlannedBlockInfo(project: project, startAt: block.startAt, note: block.note)
            }

            // Budget des laufenden bzw. (Ein-Projekt-Widget) des festen Projekts.
            var budget: WidgetSnapshot.BudgetInfo?
            let budgetProject = fixedProjectID != nil ? fixedProjectID.flatMap { projectsById[$0] } : running?.project
            if let budgetProject, let interval = budgetProject.budgetInterval {
                let used = try Self.usedTime(db, projectId: budgetProject.id, now: now)
                let runningPart = running?.project.id == budgetProject.id ? (running?.entry.duration(at: now) ?? 0) : 0
                budget = WidgetSnapshot.BudgetInfo(used: used, budget: interval, completed: max(0, used - runningPart))
            }

            return WidgetSnapshot(
                running: running,
                recent: recent,
                todayCompleted: todayCompleted,
                switchTargets: switchTargets,
                allProjects: allProjects,
                todayEntries: todayEntries,
                runningNextStep: runningNextStep,
                plannedBlock: plannedBlock,
                breakReminderMinutes: breakReminderMinutes,
                runningBudget: budget,
                fixedProjectID: fixedProjectID,
                fixedProjectRunningElsewhere: runningElsewhere,
                pomodoro: pomodoro
            )
        }
    }
}
