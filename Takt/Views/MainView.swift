import AppKit
import SwiftUI
import TaktCore

/// Hauptfenster: eigener Fensterkopf (Titel, Tabs, Zahnrad) über dem gewählten Bereich.
/// Das Fenster hat keine sichtbare Titelleiste; der Kopf liegt an ihrer Stelle.
/// ⌘K legt die Befehlspalette über das Fenster.
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
                    openSettings: { openSettings() }
                )
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
        .onOpenURL(perform: handle)
        .onAppear {
            applyNavigation()
            if CommandPaletteRequest.consume() { showPalette() }
        }
        .onChange(of: navigator?.revision) { applyNavigation() }
        .onReceive(NotificationCenter.default.publisher(for: CommandPaletteRequest.notification)) { _ in
            if CommandPaletteRequest.consume() { showPalette() }
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

    /// Unsichtbarer Knopf für ⌘K (öffnet bzw. schließt die Palette).
    private var paletteShortcut: some View {
        Button("Befehle …") {
            if isPaletteShown { hidePalette() } else { showPalette() }
        }
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
            openQuickEntryPanel: {
                paletteQuickEntry.show(store: store, settings: settings) { success in
                    showNotice(success.message)
                }
            },
            notify: showNotice
        )
    }

    private func showPalette() {
        store.refresh()
        paletteRecents = CommandRecents.load()
        withAnimation(.easeOut(duration: 0.12)) { isPaletteShown = true }
    }

    private func hidePalette() {
        withAnimation(.easeIn(duration: 0.1)) { isPaletteShown = false }
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
            try? await Task.sleep(for: .seconds(2.8))
            guard noticeID == id else { return }
            withAnimation(.easeIn(duration: 0.3)) { notice = nil }
        }
    }

    // MARK: Navigation

    /// Bereichswunsch aus dem Navigator übernehmen (Palette, Menüleiste, Mitteilungen).
    private func applyNavigation() {
        guard let requested = navigator?.consumeSection() else { return }
        section = requested
    }

    /// `takt://today` holt das Fenster nach vorn und wählt „Heute“.
    private func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "takt" else { return }
        if url.host?.lowercased() == "today" {
            section = .today
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
