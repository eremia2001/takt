import AppKit
import SwiftUI
import TaktCore

/// Hauptfenster: eigener Fensterkopf (Titel, Tabs, Zahnrad) über dem gewählten Bereich.
/// Das Fenster hat keine sichtbare Titelleiste; der Kopf liegt an ihrer Stelle.
struct MainView: View {
    @Environment(TaktStore.self) private var store
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var scheme

    @State private var section: AppSection = .today

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
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 760, minHeight: 520)
        .background(theme.window.ignoresSafeArea())
        .onOpenURL(perform: handle)
        .alert("Fehler", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
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
