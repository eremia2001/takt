import SwiftUI
import TaktCore

/// Bereich „Heute“: verbindet `TodayScreen` mit dem Store. Aktualisiert sich minütlich
/// (Dauer der Karte, Jetzt-Marke) – keine Sekunden.
struct TodayView: View {
    @Environment(TaktStore.self) private var store
    @Environment(AppSettings.self) private var settings
    /// Optional, damit „Heute“ auch ohne Kalender-Anbindung (z. B. Vorschauen) funktioniert.
    @Environment(CalendarService.self) private var calendarService: CalendarService?

    var showProjects: () -> Void = {}

    @State private var editorDraft: EntryDraft?
    @State private var pendingDeletion: TimeEntry?
    @State private var isDayOffSheetShown = false
    /// Art des freien Tags heute; der Store hält freie Tage nicht vor, daher hier nachgeladen.
    @State private var todayOff: DayOffKind?

    var body: some View {
        // Läuft etwas, im Takt des Eintrags ticken, damit `h:mm` genau zur vollen Minute springt.
        TimelineView(.periodic(from: store.running?.entry.startedAt ?? Self.startOfMinute(.now), by: 60)) { context in
            TodayScreen(data: data(now: context.date), actions: actions)
                .onChange(of: context.date) {
                    // Der längste Block wächst mit dem laufenden Eintrag.
                    if store.running != nil { store.refreshFocus(at: context.date) }
                    reloadTodayOff(now: context.date)
                }
        }
        .onAppear { reloadTodayOff() }
        .sheet(item: $editorDraft) { draft in
            EntryEditor(draft: draft)
        }
        .sheet(isPresented: $isDayOffSheetShown, onDismiss: { reloadTodayOff() }) {
            DaysOffSheet(month: .now, selected: .now)
        }
        .confirmationDialog(
            "Eintrag löschen?",
            isPresented: deletionBinding,
            presenting: pendingDeletion
        ) { entry in
            Button("Löschen", role: .destructive) {
                // Gespiegeltes Kalenderereignis zuerst entfernen – die Verknüpfung verschwindet
                // mit dem Eintrag per CASCADE.
                calendarService?.willDelete(entryId: entry.id)
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
                nextStep: entry.nextStep,
                tag: entry.tag
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

        let (events, allDay) = calendarEvents(now: now, entries: entries)

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
            plannedBlock: planned,
            todayOff: todayOff?.title,
            events: events,
            allDayEvents: allDay
        )
    }

    /// Heutige Termine (mit Uhrzeit bzw. ganztägig) samt Regel-Projekt und „erfasst“-Markierung.
    /// Leer ohne Schalter „Termine in Heute anzeigen“ oder ohne Kalenderzugriff.
    private func calendarEvents(
        now: Date, entries: [TodayData.EntryItem]
    ) -> (events: [TodayData.EventItem], allDay: [TodayData.EventItem]) {
        guard settings.calendarShowEvents, let calendarService, calendarService.hasFullAccess else { return ([], []) }
        // Regeländerungen sollen neu zeichnen; das Matching selbst liest der Store.
        _ = store.calendarRules
        var timed: [TodayData.EventItem] = []
        var allDay: [TodayData.EventItem] = []
        for info in calendarService.events(on: now) {
            let project = store.matchCalendarRule(
                calendarName: info.calendarTitle, title: info.title, attendeeDomains: info.attendeeDomains
            ).map(item)
            let captured = !info.isAllDay && entries.contains { entry in
                guard let end = entry.end else { return false }
                return abs(entry.start.timeIntervalSince(info.start)) <= 60 && abs(end.timeIntervalSince(info.end)) <= 60
            }
            let event = TodayData.EventItem(
                id: info.id, title: info.title, start: info.start, end: info.end,
                calendarTitle: info.calendarTitle, calendarColor: info.calendarColor,
                isAllDay: info.isAllDay, project: project, isCaptured: captured
            )
            if info.isAllDay { allDay.append(event) } else { timed.append(event) }
        }
        return (timed, allDay)
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
            stop: stop,
            tagSuggestions: { projectId, prefix in store.tagSuggestions(projectId: projectId, prefix: prefix) },
            previewQuickEntry: previewQuickEntry,
            commitQuickEntry: commitQuickEntry,
            resolveQuickEntry: resolveQuickEntry,
            markTodayOff: { isDayOffSheetShown = true },
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
            },
            captureEvent: captureEvent
        )
    }

    /// Termin → Eintrag: Editor vorbelegt mit Zeitraum, Regel-Projekt (sonst leer), Titel als
    /// Notiz und Tag „Meeting“ als Vorschlag.
    private func captureEvent(_ event: TodayData.EventItem) {
        let projectId = event.project?.id ?? store.projects.first?.id
        guard let projectId else { return }
        editorDraft = EntryDraft(
            entry: TimeEntry(
                projectId: projectId,
                startedAt: event.start,
                endedAt: event.end,
                nextStep: event.title,
                tag: "Meeting"
            ),
            isNew: true,
            needsProject: event.project == nil
        )
    }

    /// Stoppt den Timer; ein geändertes Tag wird vorher am laufenden Eintrag gesichert
    /// (der Store kennt kein Stoppen mit Tag).
    private func stop(nextStep: String, tag: String) {
        if var entry = store.running?.entry {
            let newTag = TimeEntry.normalizedTag(tag)
            if newTag != entry.tag {
                entry.tag = newTag
                guard store.updateEntry(entry) else { return }
            }
        }
        store.stop(nextStep: nextStep)
    }

    private func reloadTodayOff(now: Date = .now) {
        let interval = Calendar.current.dateInterval(of: .day, for: now)
            ?? DateInterval(start: Calendar.current.startOfDay(for: now), duration: 24 * 3600)
        let kind = store.daysOff(in: interval).first?.kind
        if todayOff != kind { todayOff = kind }
    }

    // MARK: Schnelleingabe

    private func previewQuickEntry(_ text: String) -> QuickEntryPreview? {
        let now = Date.now
        switch store.quickEntry(text, now: now) {
        case .success(let quick):
            guard let projectId = quick.projectId else { return .error(QuickEntryError.missingProject.errorDescription ?? "") }
            let project = item(for: projectId)
            if quick.isRunningStart {
                // Wie `TaktStore.commit`: erst ab einer Minute Abstand rückwirkend.
                let since = quick.start < now.addingTimeInterval(-60) ? quick.start : nil
                return .start(project: project, since: since, tag: quick.tag, note: quick.note)
            }
            let end = quick.end ?? now
            return .entry(project: project, day: Self.dayLabel(quick.start, now: now), start: quick.start, end: end,
                          tag: quick.tag, note: quick.note)
        case .failure(.empty):
            return nil
        case .failure(.ambiguousProject(let projects)):
            return .ambiguous(message: "Mehrere Projekte passen:", candidates: projects.map(item))
        case .failure(let error):
            return .error(error.errorDescription ?? "Die Eingabe ist unvollständig.")
        }
    }

    private func commitQuickEntry(_ text: String) -> Result<String, QuickEntryFailure> {
        let now = Date.now
        switch store.quickEntry(text, now: now) {
        case .success(let quick):
            let preview = previewQuickEntry(text)
            guard store.commit(quick) else {
                return .failure(QuickEntryFailure(message: store.consumeError() ?? "Die Eingabe konnte nicht übernommen werden."))
            }
            switch preview {
            case let .entry(project, day, start, end, _, _):
                let span = "\(TodayFormat.clock(start))–\(TodayFormat.clock(end))"
                return .success("Eingetragen: \(project.name) · \([day, span].compactMap { $0 }.joined(separator: " "))")
            case let .start(project, since, _, _):
                return .success(since.map { "Gestartet: \(project.name) seit \(TodayFormat.clock($0))" } ?? "Gestartet: \(project.name)")
            default:
                return .success("Übernommen")
            }
        case .failure(let error):
            return .failure(QuickEntryFailure(message: error.errorDescription ?? "Die Eingabe ist unvollständig."))
        }
    }

    /// Ersetzt die Wörter, die mehrdeutig auf mehrere Projekte passen, durch den vollen Namen
    /// des gewählten Projekts: probiert zusammenhängende Wortfolgen (höchstens drei Wörter) und
    /// nimmt die erste, mit der die Eingabe eindeutig dieses Projekt ergibt.
    private func resolveQuickEntry(_ text: String, _ project: TodayData.ProjectItem) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        for length in 1...min(3, max(1, words.count)) {
            for start in 0...(words.count - length) where !words[start].hasPrefix("#") {
                var candidate = words
                candidate.replaceSubrange(start..<(start + length), with: [project.name])
                let joined = candidate.joined(separator: " ")
                if case .success(let quick) = store.quickEntry(joined), quick.projectId == project.id {
                    return joined
                }
            }
        }
        return nil
    }

    /// „gestern“, „vorgestern“, sonst „Mo 19.10.“; heute `nil`.
    private static func dayLabel(_ date: Date, now: Date) -> String? {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days == 1 { return "gestern" }
        if days == 2 { return "vorgestern" }
        let weekdays = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
        let c = calendar.dateComponents([.weekday, .day, .month], from: date)
        return "\(weekdays[(c.weekday ?? 1) - 1]) \(c.day ?? 0).\(c.month ?? 0)."
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
