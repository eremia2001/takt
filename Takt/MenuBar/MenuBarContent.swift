import AppKit
import SwiftUI
import TaktCore

/// Fensterinhalt der Menüleiste: verbindet `MenuBarPanel` mit Store und Controller.
struct MenuBarContent: View {
    @Environment(TaktStore.self) private var store
    @Environment(MenuBarController.self) private var controller
    @Environment(PomodoroController.self) private var pomodoro
    @Environment(AppSettings.self) private var settings
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Minütlich neu zeichnen, solange das Fenster offen ist; keine Sekunden.
        TimelineView(.everyMinute) { context in
            // `pomodoro.tick` folgt den Restminuten der Pomodoro-Phase.
            MenuBarPanel(data: data(at: max(context.date, controller.now, pomodoro.tick)), actions: actions)
        }
        .onAppear { store.refresh() }
    }

    private func data(at now: Date) -> MenuBarPanelData {
        let running = store.running.map { state in
            MenuBarPanelData.RunningItem(project: item(state.project, now: now), start: state.entry.startedAt)
        }
        return MenuBarPanelData(
            running: running,
            projects: store.projects.map { item($0, now: now) },
            todayTotal: store.todayTotal(at: now),
            now: now,
            pomodoro: pomodoro.panelLine(at: now).map { line in
                MenuBarPanelData.PomodoroItem(text: line, isBreak: pomodoro.phase?.isBreak ?? false)
            },
            showsQuickEntryField: settings.quickEntryInMenuBar && !store.projects.isEmpty,
            quickEntryShortcut: controller.quickEntryShortcutDisplay
        )
    }

    private func item(_ project: Project, now: Date) -> MenuBarPanelData.ProjectItem {
        MenuBarPanelData.ProjectItem(
            id: project.id,
            name: project.name,
            colorHex: project.colorHex,
            isBusiness: project.isBusiness,
            todayTotal: store.todayTotal(projectId: project.id, at: now)
        )
    }

    private var actions: MenuBarPanelActions {
        MenuBarPanelActions(
            start: { controller.start($0) },
            stop: { controller.stop() },
            openApp: { controller.showMainWindow(openWindow: openWindow) },
            openSettings: {
                // Ohne Dock-Symbol muss die App erst aktiv werden, sonst bleibt das Fenster hinten.
                NSApp.activate()
                openSettings()
            },
            quit: { NSApp.terminate(nil) },
            skipPomodoroPhase: { pomodoro.skipPhase() },
            quickEntry: QuickEntryEngine(store: store).handlers,
            openQuickEntry: { controller.showQuickEntry() }
        )
    }
}

/// Anzeige in der Menüleiste je nach Stil (`menuBarStyle`) als fertiges Bild
/// (`MenuBarLabelRenderer`): läuft ein Timer → Projektfarbe und Zeit, sonst die Ring-Glyphe.
struct MenuBarLabel: View {
    @Environment(TaktStore.self) private var store
    @Environment(MenuBarController.self) private var controller
    @Environment(PomodoroController.self) private var pomodoro

    var body: some View {
        // `controller.now` tickt minütlich, `pomodoro.tick` zur vollen Restminute; beide lösen das
        // Neuzeichnen aus, ebenso Einstellungen, Store und die Helligkeit der Menüleiste.
        let now = max(controller.now, pomodoro.tick, .now)
        let model = Self.model(store: store, settings: controller.settings, pomodoro: pomodoro,
                               now: now, isDark: controller.menuBarIsDark)
        Image(nsImage: MenuBarLabelRenderer.image(for: model))
            .accessibilityLabel(model.accessibilityText)
    }

    /// Zustand des Labels aus Store, Einstellungen und Pomodoro.
    static func model(store: TaktStore, settings: AppSettings, pomodoro: PomodoroController,
                      now: Date, isDark: Bool) -> MenuBarLabelModel {
        let running = store.running.map { state -> MenuBarLabelModel.Running in
            let budgetFraction: Double? = state.project.budgetInterval.flatMap { budget in
                store.budgetUsed(projectId: state.project.id, at: now).map { $0 / budget }
            }
            return MenuBarLabelModel.Running(
                name: state.project.name,
                colorHex: state.project.colorHex,
                elapsed: state.entry.duration(at: now),
                budgetFraction: budgetFraction
            )
        }
        let pomodoroItem = pomodoro.status(at: now).map { status -> MenuBarLabelModel.Pomodoro in
            let minutes = switch status.phase {
            case .work: settings.pomodoroWorkMinutes
            case .shortBreak: settings.pomodoroBreakMinutes
            case .longBreak: settings.pomodoroLongBreakMinutes
            }
            let total = max(60, TimeInterval(minutes) * 60)
            return MenuBarLabelModel.Pomodoro(
                isBreak: status.phase.isBreak,
                clock: PomodoroController.clock(status.remaining),
                progress: min(1, max(0, 1 - status.remaining / total))
            )
        }
        return MenuBarLabelModel(
            style: settings.menuBarStyle,
            showProjectName: settings.menuBarShowProjectName,
            showTodayTotal: settings.menuBarShowTodayTotal,
            idleMode: settings.menuBarIdleMode,
            running: running,
            todayTotal: store.todayTotal(at: now),
            pomodoro: pomodoroItem,
            isDark: isDark
        )
    }

    /// Ob das Menüleistenobjekt eingefügt sein soll: Pause-Darstellung „Ausblenden“ entfernt es,
    /// solange weder Timer noch Pomodoro-Phase laufen (für `MenuBarExtra(isInserted:)`).
    static func isVisible(settings: AppSettings, store: TaktStore, pomodoro: PomodoroController) -> Bool {
        settings.menuBarIdleMode != .hidden || store.running != nil || pomodoro.status(at: .now) != nil
    }
}
