import AppKit
import Foundation
import SwiftUI
import TaktCore

/// Baut die Befehle der Palette aus Store, Einstellungen und Navigator.
/// Fenster-Aktionen (Einstellungen öffnen, Hinweis zeigen, Schnelleingabe-Fenster) kommen
/// als Closures von `MainView`, weil nur die View sie kennt.
@MainActor
struct CommandRegistry {
    let store: TaktStore
    let settings: AppSettings
    let navigator: AppNavigator?
    /// Bereich direkt umschalten (falls kein Navigator in der Umgebung ist).
    var selectSection: (AppSection) -> Void = { _ in }
    /// Einstellungen-Fenster nach vorn holen.
    var openSettings: () -> Void = {}
    /// Schwebendes Schnelleingabe-Fenster öffnen.
    var openQuickEntryPanel: () -> Void = {}
    /// Kurzer Hinweis im Hauptfenster (Bestätigung, Tipp).
    var notify: (String) -> Void = { _ in }

    /// Reiter der Einstellungen: Kennung (wie in `SettingsView`), Titel, Symbol, Suchbegriffe.
    static let settingsTabs: [(id: String, title: String, icon: String, keywords: [String])] = [
        ("general", "Allgemein", "gearshape", ["general", "rundung", "stundensatz", "wochenziel", "menüleiste", "kurzbefehl"]),
        ("music", "Musik", "music.note", ["spotify", "apple music", "playlist"]),
        ("focus", "Fokus", "scope", ["pomodoro", "pause", "leerlauf", "konzentration"]),
        ("widget", "Widget", "square.grid.2x2", ["schreibtisch", "desktop"]),
        ("billing", "Abrechnung", "eurosign.circle", ["rechnung", "stundensatz", "währung", "budget", "billing"]),
        ("calendar", "Kalender", "calendar", ["termine", "eventkit", "spiegeln"]),
        ("activity", "Aktivität", "waveform.path.ecg", ["apps", "fenster", "repository", "regeln", "erkennung"]),
        ("notifications", "Mitteilungen", "bell", ["benachrichtigungen", "hinweise", "notifications"]),
    ]

    // MARK: Befehle

    func commands(now: Date = .now) -> [Command] {
        timerCommands(now: now) + projectCommands() + navigationCommands() + reportCommands()
            + exportCommands(now: now) + settingsCommands() + quickEntryCommands() + helpCommands()
    }

    private func timerCommands(now: Date) -> [Command] {
        var result: [Command] = []
        if let running = store.running {
            let project = running.project
            result.append(Command(
                id: "timer.stop",
                title: "Stoppen",
                subtitle: "\(project.name) · \(DurationFormat.hourMinute(running.entry.duration(at: now)))",
                group: .timer,
                keywords: ["stop", "anhalten", "beenden", "timer", "pause"],
                icon: "stop.circle",
                priority: 6,
                perform: { [store] in
                    let duration = running.entry.duration(at: .now)
                    if store.stop(nextStep: nil) {
                        notify("\(project.name) gestoppt · \(DurationFormat.hourMinute(duration))")
                    }
                }
            ))
        } else if let last = store.lastUsedProject {
            result.append(Command(
                id: "timer.resume",
                title: "Weiter mit \(last.name)",
                subtitle: store.lastNextSteps[last.id],
                group: .timer,
                keywords: ["fortsetzen", "resume", "starten", "timer", "letztes"],
                icon: "play.circle",
                priority: 6,
                perform: { [store] in
                    if store.start(projectId: last.id) { notify("\(last.name) gestartet") }
                }
            ))
        }
        return result
    }

    private func projectCommands() -> [Command] {
        let runningId = store.running?.project.id
        var result: [Command] = store.projects
            .filter { $0.id != runningId }
            .map { project in
                Command(
                    id: "project.start.\(project.id.uuidString)",
                    title: "Starten: \(project.name)",
                    subtitle: project.client,
                    group: .projects,
                    keywords: ["start", "timer", project.isBusiness ? "business" : "privat"],
                    icon: "circle.fill",
                    colorHex: project.colorHex,
                    badge: project.isBusiness ? "Business" : "Privat",
                    priority: 4,
                    perform: { [store] in
                        if store.start(projectId: project.id) { notify("\(project.name) gestartet") }
                    }
                )
            }
        result.append(Command(
            id: "project.new",
            title: "Neues Projekt …",
            group: .projects,
            keywords: ["anlegen", "erstellen", "hinzufügen", "new", "project"],
            icon: "plus.circle",
            perform: {
                select(.projects)
                notify("Neues Projekt: oben rechts auf „+ Projekt“ klicken")
            }
        ))
        result += store.projects.map { project in
            Command(
                id: "project.archive.\(project.id.uuidString)",
                title: "Archivieren: \(project.name)",
                group: .projects,
                keywords: ["archiv", "ausblenden", "archive"],
                icon: "archivebox",
                colorHex: project.colorHex,
                showsWhenEmpty: false,
                priority: -20,
                confirmation: CommandConfirmation(
                    title: "„\(project.name)“ archivieren?",
                    message: "Das Projekt verschwindet aus „Heute“, Menüleiste und Widget. "
                        + "Einträge bleiben erhalten; unter Projekte lässt es sich wiederherstellen.",
                    actionTitle: "Archivieren"
                ),
                perform: { [store] in
                    if store.archive(project) { notify("„\(project.name)“ archiviert") }
                }
            )
        }
        return result
    }

    private func navigationCommands() -> [Command] {
        let sections: [(AppSection, String, [String])] = [
            (.today, "sun.max", ["today", "tag", "start"]),
            (.reports, "chart.bar", ["reports", "auswertung", "statistik"]),
            (.projects, "folder", ["projects", "kunden", "liste"]),
        ]
        var result = sections.map { section, icon, keywords in
            Command(
                id: "nav.\(section.rawValue)",
                title: section.title,
                subtitle: "Bereich",
                group: .navigation,
                keywords: keywords + ["gehe zu", "öffnen"],
                icon: icon,
                perform: { select(section) }
            )
        }
        result.append(Command(
            id: "nav.settings",
            title: "Einstellungen",
            subtitle: "Fenster öffnen",
            group: .navigation,
            keywords: ["settings", "optionen", "preferences", "voreinstellungen"],
            icon: "gearshape",
            perform: { openSettings() }
        ))
        return result
    }

    private func reportCommands() -> [Command] {
        let kinds: [(ReportPeriodKind, String, [String])] = [
            (.day, "calendar.day.timeline.left", ["heute", "tagesbericht", "day"]),
            (.week, "calendar", ["kw", "kalenderwoche", "week", "wochenbericht"]),
            (.month, "calendar.badge.clock", ["monatsbericht", "month"]),
            (.year, "chart.bar.xaxis", ["jahresbericht", "jahresübersicht", "year"]),
        ]
        return kinds.map { kind, icon, keywords in
            Command(
                id: "report.\(kind.rawValue)",
                title: "Bericht: \(kind.title)",
                group: .reports,
                keywords: keywords + ["auswertung", "report"],
                icon: icon,
                perform: { [navigator] in
                    if let navigator {
                        navigator.request(reportKind: kind)
                    } else {
                        selectSection(.reports)
                    }
                }
            )
        }
    }

    private func exportCommands(now: Date) -> [Command] {
        let month = Self.monthTitle(now)
        return [
            Command(
                id: "export.entries",
                title: "Einträge als CSV …",
                subtitle: month,
                group: .export,
                keywords: ["export", "excel", "datei", "speichern", "csv"],
                icon: "tablecells",
                perform: { export(.entries) }
            ),
            Command(
                id: "export.summary",
                title: "Zusammenfassung als CSV …",
                subtitle: month,
                group: .export,
                keywords: ["export", "excel", "datei", "speichern", "csv", "projekte", "summen"],
                icon: "list.bullet.rectangle",
                perform: { export(.summary) }
            ),
        ]
    }

    private func settingsCommands() -> [Command] {
        Self.settingsTabs.map { tab in
            Command(
                id: "settings.\(tab.id)",
                title: "Einstellungen: \(tab.title)",
                group: .settings,
                keywords: tab.keywords + ["settings", "optionen"],
                icon: tab.icon,
                showsWhenEmpty: false,
                perform: { [navigator] in
                    navigator?.request(settingsTab: tab.id)
                    openSettings()
                }
            )
        }
    }

    private func quickEntryCommands() -> [Command] {
        [Command(
            id: "quickentry.panel",
            title: "Schnelleingabe-Fenster öffnen",
            subtitle: settings.quickEntryHotKeyEnabled ? Self.quickEntryShortcut(settings) : nil,
            group: .quickEntry,
            keywords: ["eintrag", "quick entry", "spotlight", "erfassen", "nachtragen"],
            icon: "pencil.line",
            perform: { openQuickEntryPanel() }
        )]
    }

    /// Hilfe: „Takt-Hilfe“ (immer sichtbar), „Hilfe: <Thema>“ je Thema und „Einführung zeigen“
    /// (beide erst bei Suche). Gruppe „Navigation“, weil sie ein Fenster bzw. Sheet öffnen.
    private func helpCommands() -> [Command] {
        var result = [Command(
            id: "help.open",
            title: "Takt-Hilfe",
            subtitle: "⌘?",
            group: .navigation,
            keywords: ["hilfe", "help", "anleitung", "handbuch", "erklärung", "fragen"],
            icon: "questionmark.circle",
            perform: { showHelp(nil) }
        )]
        result += HelpContent.topics.map { topic in
            Command(
                id: "help.\(topic.id)",
                title: "Hilfe: \(topic.title)",
                subtitle: topic.summary,
                group: .navigation,
                keywords: topic.keywords + ["hilfe", "help", "anleitung", "wie"],
                icon: topic.icon,
                showsWhenEmpty: false,
                priority: -4,
                perform: { showHelp(topic.id) }
            )
        }
        result.append(Command(
            id: "help.onboarding",
            title: "Einführung zeigen",
            subtitle: "Die fünf Seiten vom ersten Start",
            group: .navigation,
            keywords: ["onboarding", "einführung", "tour", "willkommen", "erste schritte"],
            icon: "sparkles",
            showsWhenEmpty: false,
            perform: { [navigator] in navigator?.requestOnboarding() }
        ))
        return result
    }

    private func showHelp(_ topicID: String?) {
        if let topicID, let navigator {
            navigator.request(helpTopic: topicID)
        } else {
            HelpCenter.shared.show(topicID: topicID)
        }
    }

    // MARK: Schnelleingabe-Treffer

    /// Treffer für Text, der wie eine Schnelleingabe aussieht: Ziffern oder `#` im Text (Zeit, Tag)
    /// oder kein Befehl passt. Ein bloßer Start ohne Zusatz fehlt – den deckt „Starten: …“ ab.
    /// Bei mehrdeutigem Projekt je Kandidat ein Treffer (höchstens drei).
    func suggestions(for text: String, hasCommandMatch: Bool) -> [Command] {
        let looksLikeEntry = text.contains(where: { $0.isNumber || $0 == "#" })
        guard looksLikeEntry || !hasCommandMatch, !store.projects.isEmpty else { return [] }
        let engine = QuickEntryEngine(store: store)
        switch engine.preview(text) {
        case let preview? where preview.isValid:
            return suggestion(text: text, preview: preview, index: 0, requiresExtra: true).map { [$0] } ?? []
        case let .ambiguous(_, candidates)?:
            return candidates.prefix(3).enumerated().compactMap { index, candidate in
                guard let resolved = engine.resolve(text, candidate),
                      let preview = engine.preview(resolved), preview.isValid else { return nil }
                return suggestion(text: resolved, preview: preview, index: index, requiresExtra: false)
            }
        default:
            return []
        }
    }

    private func suggestion(text: String, preview: QuickEntryPreview, index: Int, requiresExtra: Bool) -> Command? {
        let title: String
        let details: [String?]
        let project: TodayData.ProjectItem
        let icon: String
        switch preview {
        case let .entry(item, day, start, end, tag, note):
            project = item
            title = "Eintragen: \(item.name)"
            details = [day, "\(TodayFormat.clock(start))–\(TodayFormat.clock(end))",
                       TodayFormat.duration(end.timeIntervalSince(start)), tag.map { "#\($0)" }, note]
            icon = "plus"
        case let .start(item, since, tag, note):
            // Bloßer Start ohne Zusatz: doppelt zu „Starten: <Projekt>“.
            if requiresExtra, since == nil, tag == nil, note == nil { return nil }
            project = item
            title = "Starten: \(item.name)"
            details = [since.map { "ab \(TodayFormat.clock($0))" } ?? "jetzt", tag.map { "#\($0)" }, note]
            icon = "play.fill"
        case .ambiguous, .error:
            return nil
        }
        return Command(
            id: "quickentry.suggestion.\(index)",
            title: title,
            subtitle: details.compactMap { $0 }.joined(separator: " · "),
            group: .quickEntry,
            icon: icon,
            colorHex: project.colorHex,
            isTransient: true,
            perform: { [store] in
                switch QuickEntryEngine(store: store).commit(text) {
                case .success(let success): notify(success.message)
                case .failure(let failure): store.lastError = failure.message
                }
            }
        )
    }

    // MARK: Aktionen

    private func select(_ section: AppSection) {
        if let navigator {
            navigator.request(section: section)
        } else {
            selectSection(section)
        }
    }

    /// CSV des laufenden Monats über den Sichern-Dialog (wie im Bereich „Berichte“).
    /// Auch für das App-Menü (Ablage › Einträge als CSV exportieren …).
    func export(_ kind: CSVExporter.Kind) {
        let now = Date.now
        let period = ReportPeriod.month(now)
        guard let report = store.report(
            for: period,
            rounding: settings.rounding,
            defaultHourlyRate: settings.defaultHourlyRate,
            weeklyGoal: settings.weeklyGoal,
            now: now
        ) else { return }
        let content: String
        switch kind {
        case .entries:
            content = CSVExport.entries(
                store.entries(in: report.interval).sorted { $0.startedAt < $1.startedAt },
                projects: Array(store.projectsById.values),
                rounding: settings.rounding,
                calendar: .current,
                defaultHourlyRate: settings.defaultHourlyRate,
                now: now
            )
        case .summary, .year:
            content = CSVExport.summary(report, calendar: .current)
        }
        let name = CSVExporter.fileName(kind, period: period)
        Task { @MainActor [store] in
            do {
                if let url = try await CSVExporter.save(content, suggestedName: name) {
                    notify("Gespeichert: \(url.lastPathComponent)")
                }
            } catch {
                store.lastError = "Die Datei konnte nicht gespeichert werden: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Hilfen

    static func quickEntryShortcut(_ settings: AppSettings) -> String {
        KeyCombo(keyCode: settings.quickEntryHotKeyKeyCode,
                 modifiers: NSEvent.ModifierFlags(rawValue: settings.quickEntryHotKeyModifiers)).display
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    /// „Oktober 2026“.
    static func monthTitle(_ date: Date) -> String {
        monthFormatter.string(from: date)
    }
}

/// Schwebendes Schnelleingabe-Fenster aus der Palette. Eigene Instanz, weil `MainView` den
/// `MenuBarController` nicht kennt; gleiches Fenster und gleiche Regeln (`QuickEntryEngine`).
@MainActor
final class CommandPaletteQuickEntry {
    private var panel: QuickEntryPanelController?

    func show(store: TaktStore, settings: AppSettings, onSuccess: @escaping (QuickEntrySuccess) -> Void) {
        let panel = panel ?? QuickEntryPanelController(
            handlers: { [weak store] in
                guard let store else { return QuickEntryHandlers() }
                store.refresh()
                return QuickEntryEngine(store: store).handlers
            },
            shortcut: { [weak settings] in
                guard let settings, settings.quickEntryHotKeyEnabled else { return nil }
                return CommandRegistry.quickEntryShortcut(settings)
            },
            onSuccess: onSuccess
        )
        self.panel = panel
        panel.show()
    }
}
