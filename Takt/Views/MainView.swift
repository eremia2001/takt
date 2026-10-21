import AppKit
import SwiftUI
import TaktCore

/// Hauptfenster: eigener Fensterkopf (Titel, Tabs, Befehle, Hilfe, Zahnrad) über dem gewählten Bereich.
/// Das Fenster hat keine sichtbare Titelleiste; der Kopf liegt an ihrer Stelle.
/// ⌘K legt die Befehlspalette über das Fenster.
///
/// Außerdem: Einführung beim ersten Start (Sheet), einmaliger Hinweis „Neu: …“ für bestehende
/// Nutzer und die Aktionen aus dem App-Menü (`AppNavigator.requestedAction`), die keine Ansicht
/// selbst übernimmt (Neuer Eintrag, Neues Projekt, Export, Toggl-Import).
struct MainView: View {
    @Environment(TaktStore.self) private var store
    @Environment(AppSettings.self) private var settings
    /// Optional, damit das Fenster auch ohne Navigator (z. B. Vorschauen) funktioniert.
    @Environment(AppNavigator.self) private var navigator: AppNavigator?
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var scheme

    @State private var section: AppSection = .today
    @State private var isPaletteShown = false
    @State private var paletteRecents: [String] = []
    @State private var paletteQuickEntry = CommandPaletteQuickEntry()
    /// Kurzer Hinweis unten im Fenster (Bestätigungen aus der Palette).
    @State private var notice: String?
    @State private var noticeID = 0
    /// Sheet des Hauptfensters (Einführung, Fallbacks für Menü-Aktionen).
    @State private var sheet: MainSheet?
    /// Einmaliger Hinweis „Neu: Befehlspalette ⌘K …“ unter dem Kopf.
    @State private var isWhatsNewShown = false
    /// Menü-Aktion, die gerade an einen Bereich weitergereicht wird.
    @State private var pendingAction: AppAction?

    private var theme: DesignTheme { DesignTheme(scheme: scheme) }

    var body: some View {
        VStack(spacing: 0) {
            // Datum minütlich prüfen, damit es nach Mitternacht stimmt.
            TimelineView(.everyMinute) { context in
                WindowHeader(
                    title: TodayFormat.day(context.date),
                    selection: section,
                    theme: theme,
                    select: { section = $0 },
                    openSettings: { openSettings() },
                    openPalette: togglePalette,
                    openHelp: { HelpCenter.shared.show() }
                )
            }

            if isWhatsNewShown {
                WhatsNewBanner(
                    openPalette: {
                        dismissWhatsNew()
                        showPalette()
                    },
                    openHelp: {
                        dismissWhatsNew()
                        HelpCenter.shared.show(topicID: "palette")
                    },
                    dismiss: dismissWhatsNew
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            switch section {
            case .today: TodayView(showProjects: { section = .projects })
            case .reports: ReportsView()
            case .projects: ProjectsView()
            }
        }
        // Solange die Palette offen ist, greifen die Kurzbefehle darunter (⌘1–3, ⌘N …) nicht –
        // ⌘1–9 gehören dann der Palette.
        .disabled(isPaletteShown)
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 760, minHeight: 520)
        .background(theme.window.ignoresSafeArea())
        .overlay(alignment: .bottom) { noticeView }
        .overlay { palette }
        .background { paletteShortcut }
        .registerHelpWindowOpener()
        .onOpenURL(perform: handle)
        .onAppear {
            applyNavigation()
            if CommandPaletteRequest.consume() { showPalette() }
            checkFirstLaunch()
        }
        .onChange(of: navigator?.revision) { applyNavigation() }
        .onChange(of: navigator?.paletteToggleRevision) { togglePalette() }
        .onReceive(NotificationCenter.default.publisher(for: CommandPaletteRequest.notification)) { _ in
            if CommandPaletteRequest.consume() { showPalette() }
        }
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
        }
        .alert("Fehler", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }

    // MARK: Befehlspalette

    @ViewBuilder
    private var palette: some View {
        if isPaletteShown {
            let registry = registry
            CommandPaletteOverlay(
                commands: registry.commands(),
                suggestions: { registry.suggestions(for: $0, hasCommandMatch: $1) },
                recentIDs: paletteRecents,
                topInset: WindowHeader.height + 18,
                run: run,
                close: hidePalette
            )
            .transition(.opacity)
        }
    }

    /// Unsichtbarer Knopf für ⌘K (öffnet bzw. schließt die Palette). Das App-Menü
    /// (Timer › Befehle …) hat dasselbe Kürzel; im Hauptfenster greift dieser Knopf zuerst.
    private var paletteShortcut: some View {
        Button("Befehle …", action: togglePalette)
            .keyboardShortcut("k", modifiers: .command)
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    private var registry: CommandRegistry {
        CommandRegistry(
            store: store,
            settings: settings,
            navigator: navigator,
            selectSection: { section = $0 },
            openSettings: {
                NSApp.activate()
                openSettings()
            },
            openQuickEntryPanel: openQuickEntryPanel,
            notify: showNotice
        )
    }

    private func openQuickEntryPanel() {
        paletteQuickEntry.show(store: store, settings: settings) { success in
            showNotice(success.message)
        }
    }

    private func togglePalette() {
        if isPaletteShown { hidePalette() } else { showPalette() }
    }

    private func showPalette() {
        guard sheet == nil else { return }
        store.refresh()
        paletteRecents = CommandRecents.load()
        withAnimation(.easeOut(duration: 0.12)) { isPaletteShown = true }
        navigator?.isPaletteShown = true
    }

    private func hidePalette() {
        withAnimation(.easeIn(duration: 0.1)) { isPaletteShown = false }
        navigator?.isPaletteShown = false
    }

    /// Palette schließen, dann ausführen – Dialoge (Sichern, Einstellungen) sollen nicht
    /// hinter dem Overlay aufgehen.
    private func run(_ command: Command) {
        if !command.isTransient { CommandRecents.record(command.id) }
        hidePalette()
        DispatchQueue.main.async { command.perform() }
    }

    // MARK: Hinweis

    @ViewBuilder
    private var noticeView: some View {
        if let notice {
            Text(notice)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .padding(.bottom, 18)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .allowsHitTesting(false)
        }
    }

    private func showNotice(_ text: String) {
        noticeID += 1
        let id = noticeID
        withAnimation(.easeOut(duration: 0.18)) { notice = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(text.count > 50 ? 4.5 : 2.8))
            guard noticeID == id else { return }
            withAnimation(.easeIn(duration: 0.3)) { notice = nil }
        }
    }

    // MARK: Einführung und „Neu“

    /// Beim ersten Erscheinen: Einführung ohne Projekte, sonst einmalig der Hinweis „Neu: …“.
    private func checkFirstLaunch() {
        let hasProjects = !store.projectsById.isEmpty
        if OnboardingInfo.shouldShowOnboarding(hasProjects: hasProjects, databaseFailed: store.lastError != nil) {
            OnboardingInfo.markShown()
            sheet = .onboarding
            return
        }
        guard hasProjects else { return }
        // Bestehende Nutzer brauchen keine Einführung mehr.
        if !settings.onboardingCompleted { settings.onboardingCompleted = true }
        if OnboardingInfo.shouldShowWhatsNew(seenVersion: settings.onboardingVersion) {
            // Gilt als gesehen, sobald er einmal erscheint („einmalig“); sichtbar bis zum Ausblenden.
            settings.onboardingVersion = OnboardingInfo.currentVersion
            isWhatsNewShown = true
            // Der Tipp in „Heute“ sagt fast dasselbe – bestehende Nutzer sehen nur den Hinweis.
            TipStore.shared.dismiss(.today)
        }
    }

    private func dismissWhatsNew() {
        withAnimation(.easeOut(duration: 0.2)) { isWhatsNewShown = false }
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: MainSheet) -> some View {
        switch sheet {
        case .onboarding:
            OnboardingSheet()
        case .newEntry(let draft):
            EntryEditor(draft: draft)
        case .newProject(let draft):
            ProjectEditor(draft: draft)
        case .timesheet(let interval):
            TimesheetExportSheet(initialInterval: interval) { name in
                showNotice("Gespeichert: \(name)")
            }
        case .togglImport:
            TogglImportSheet()
        }
    }

    // MARK: Navigation

    /// Wünsche aus dem Navigator übernehmen (Palette, Menüleiste, App-Menü, Mitteilungen).
    private func applyNavigation() {
        guard let navigator else { return }
        if let requested = navigator.consumeSection() {
            section = requested
        }
        // Das Hilfe-Fenster öffnet `HelpCenter` selbst; hier nur den Wunsch abräumen.
        navigator.consumeHelpTopic()
        if navigator.consumeOnboarding() {
            hidePalette()
            sheet = .onboarding
        }
        if let action = navigator.requestedAction, action != pendingAction {
            forward(action)
        }
    }

    /// Menü-Aktion an den zuständigen Bereich weiterreichen. Übernimmt ihn dort niemand
    /// (`consumeAction`), führt `MainView` sie selbst aus bzw. zeigt, wo es weitergeht.
    private func forward(_ action: AppAction) {
        pendingAction = action
        hidePalette()
        switch action {
        case .exportEntriesCSV, .exportSummaryCSV, .exportTimesheetPDF, .importToggl: section = .reports
        case .planBlock, .newEntry: section = .today
        case .newProject: section = .projects
        }
        Task { @MainActor in
            // Dem neuen Bereich Zeit geben, die Anforderung selbst zu übernehmen.
            try? await Task.sleep(for: .milliseconds(200))
            defer { pendingAction = nil }
            guard let navigator, navigator.requestedAction == action else { return }
            navigator.consumeAction()
            perform(action)
        }
    }

    private func perform(_ action: AppAction) {
        switch action {
        case .exportEntriesCSV:
            registry.export(.entries)
        case .exportSummaryCSV:
            registry.export(.summary)
        case .exportTimesheetPDF:
            let calendar = Calendar.current
            let month = calendar.dateInterval(of: .month, for: .now)
                ?? DateInterval(start: calendar.startOfDay(for: .now), duration: 24 * 3600)
            sheet = .timesheet(month)
        case .importToggl:
            sheet = .togglImport
        case .newProject:
            sheet = .newProject(ProjectDraft(project: nil))
        case .newEntry:
            guard let projectId = store.lastUsedProject?.id ?? store.projects.first?.id else {
                section = .projects
                showNotice("Lege zuerst ein Projekt an: oben rechts auf „+ Projekt“ klicken")
                return
            }
            let now = Date.now
            sheet = .newEntry(EntryDraft(
                entry: TimeEntry(projectId: projectId, startedAt: now.addingTimeInterval(-3600), endedAt: now),
                isNew: true
            ))
        case .planBlock:
            showNotice("Block planen: in „Heute“ unter der Karte auf „Block planen …“ klicken")
        }
    }

    /// `takt://today` holt das Fenster nach vorn und wählt „Heute“; `takt://help/<thema>` öffnet
    /// die Hilfe, `takt://onboarding` die Einführung.
    private func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "takt" else { return }
        switch url.host?.lowercased() {
        case "today":
            section = .today
        case "help":
            HelpCenter.shared.show(topicID: url.pathComponents.dropFirst().first)
            return
        case "onboarding":
            sheet = .onboarding
        default:
            break
        }
        NSApp.activate()
        NSApp.windows
            .first { $0.isVisible && $0.canBecomeMain }?
            .makeKeyAndOrderFront(nil)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )
    }
}

/// Sheets des Hauptfensters.
private enum MainSheet: Identifiable {
    case onboarding
    case newEntry(EntryDraft)
    case newProject(ProjectDraft)
    case timesheet(DateInterval)
    case togglImport

    var id: String {
        switch self {
        case .onboarding: "onboarding"
        case .newEntry(let draft): "entry-\(draft.id)"
        case .newProject(let draft): "project-\(draft.id)"
        case .timesheet(let interval): "timesheet-\(interval.start.timeIntervalSince1970)"
        case .togglImport: "toggl"
        }
    }
}
