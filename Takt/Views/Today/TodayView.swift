import SwiftUI
import TaktCore

/// Bereich „Heute“: verbindet `TodayScreen` mit dem Store. Aktualisiert sich minütlich
/// (Dauer der Karte, Jetzt-Marke) – keine Sekunden.
struct TodayView: View {
    @Environment(TaktStore.self) private var store

    var showProjects: () -> Void = {}

    @State private var editorDraft: EntryDraft?
    @State private var pendingDeletion: TimeEntry?

    var body: some View {
        // Läuft etwas, im Takt des Eintrags ticken, damit `h:mm` genau zur vollen Minute springt.
        TimelineView(.periodic(from: store.running?.entry.startedAt ?? Self.startOfMinute(.now), by: 60)) { context in
            TodayScreen(data: data(now: context.date), actions: actions)
                .onChange(of: context.date) {
                    // Der längste Block wächst mit dem laufenden Eintrag.
                    if store.running != nil { store.refreshFocus(at: context.date) }
                }
        }
        .sheet(item: $editorDraft) { draft in
            EntryEditor(draft: draft)
        }
        .confirmationDialog(
            "Eintrag löschen?",
            isPresented: deletionBinding,
            presenting: pendingDeletion
        ) { entry in
            Button("Löschen", role: .destructive) {
                store.deleteEntry(entry)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { _ in
            Text("Der Eintrag wird endgültig entfernt.")
        }
    }

    // MARK: Daten

    private func data(now: Date) -> TodayData {
        let entries = store.todayEntries.reversed().map { entry in
            TodayData.EntryItem(
                id: entry.id,
                project: item(for: entry.projectId),
                start: entry.startedAt,
                end: entry.endedAt,
                nextStep: entry.nextStep
            )
        }

        var resume: TodayData.Resume?
        var runningNextStep: String?
        if let running = store.running {
            runningNextStep = store.lastNextSteps[running.project.id]
        } else if let last = store.lastUsedProject {
            resume = TodayData.Resume(project: item(last), nextStep: store.lastNextSteps[last.id])
        }

        // Geplanter Block: abgelaufene (mehr als 4 h nach Beginn) ausblenden, auch ohne neues Laden.
        var planned: TodayData.PlannedItem?
        if let block = store.plannedBlock,
           block.startAt >= now.addingTimeInterval(-AppDatabase.plannedBlockGrace),
           let project = store.project(id: block.projectId), !project.isArchived {
            planned = TodayData.PlannedItem(project: item(project), startAt: block.startAt, note: block.note)
        }

        return TodayData(
            now: now,
            dayStart: Calendar.current.startOfDay(for: now),
            projects: store.projects.map(item),
            entries: entries,
            todayTotal: store.todayTotal(at: now),
            switches: store.todayFocus.switches,
            longestBlock: store.todayFocus.longestBlock,
            resume: resume,
            runningNextStep: runningNextStep,
            plannedBlock: planned
        )
    }

    private func item(_ project: Project) -> TodayData.ProjectItem {
        TodayData.ProjectItem(
            id: project.id,
            name: project.name,
            colorHex: project.colorHex,
            isBusiness: project.isBusiness
        )
    }

    private func item(for projectId: UUID) -> TodayData.ProjectItem {
        if let project = store.project(id: projectId) { return item(project) }
        return TodayData.ProjectItem(id: projectId, name: "Unbekanntes Projekt", colorHex: "", isBusiness: false)
    }

    // MARK: Aktionen

    private var actions: TodayActions {
        TodayActions(
            start: { project in _ = store.start(projectId: project.id) },
            stop: { nextStep in _ = store.stop(nextStep: nextStep) },
            openEntry: { item in
                if let entry = entry(id: item.id) {
                    editorDraft = EntryDraft(entry: entry, isNew: false)
                }
            },
            deleteEntry: { item in pendingDeletion = entry(id: item.id) },
            addEntry: addEntry,
            showProjects: showProjects,
            startPlannedBlock: { store.startPlannedBlock() },
            clearPlannedBlock: { store.clearPlannedBlock() },
            planBlock: { projectId, startAt, note in
                store.planBlock(projectId: projectId, startAt: startAt, note: note)
            }
        )
    }

    private func entry(id: UUID) -> TimeEntry? {
        store.todayEntries.first { $0.id == id }
    }

    /// Neuer Eintrag: letzte volle Stunde bis jetzt, zuletzt genutztes Projekt.
    private func addEntry() {
        let now = Date.now
        let calendar = Calendar.current
        var start = calendar.dateInterval(of: .hour, for: now)?.start ?? now.addingTimeInterval(-3600)
        // Direkt nach der vollen Stunde wäre der Eintrag fast leer – dann die Stunde davor.
        if now.timeIntervalSince(start) < 60 {
            start = start.addingTimeInterval(-3600)
        }
        let activeIds = Set(store.projects.map(\.id))
        let projectId = store.todayEntries.first { activeIds.contains($0.projectId) }?.projectId
            ?? store.projects.first?.id
        guard let projectId else { return }
        editorDraft = EntryDraft(
            entry: TimeEntry(projectId: projectId, startedAt: start, endedAt: now),
            isNew: true
        )
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private static func startOfMinute(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .minute, for: date)?.start ?? date
    }
}
