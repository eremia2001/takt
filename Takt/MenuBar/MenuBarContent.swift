import AppKit
import SwiftUI
import TaktCore

/// Fensterinhalt der Menüleiste: verbindet `MenuBarPanel` mit Store und Controller.
struct MenuBarContent: View {
    @Environment(TaktStore.self) private var store
    @Environment(MenuBarController.self) private var controller
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Minütlich neu zeichnen, solange das Fenster offen ist; keine Sekunden.
        TimelineView(.everyMinute) { context in
            MenuBarPanel(data: data(at: max(context.date, controller.now)), actions: actions)
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
            now: now
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
            quit: { NSApp.terminate(nil) }
        )
    }
}

/// Anzeige in der Menüleiste: läuft ein Timer → Farbpunkt + „Projekt · h:mm“, sonst das Takt-Symbol.
struct MenuBarLabel: View {
    @Environment(TaktStore.self) private var store
    @Environment(MenuBarController.self) private var controller

    /// Längere Namen kürzen, damit die Menüleiste nicht vollläuft.
    private static let maxNameLength = 22

    var body: some View {
        if let running = store.running {
            // `controller.now` tickt minütlich und löst das Neuzeichnen aus.
            let duration = running.entry.duration(at: max(controller.now, .now))
            HStack(spacing: 5) {
                Image(nsImage: Self.dot(hex: running.project.colorHex))
                Text("\(Self.shortened(running.project.name)) · \(DurationFormat.hourMinute(duration))")
                    .monospacedDigit()
            }
            .accessibilityLabel("\(running.project.name) läuft seit \(DurationFormat.hourMinute(duration))")
        } else {
            Image(systemName: "circle.dotted")
                .accessibilityLabel("Takt – nichts läuft")
        }
    }

    static func shortened(_ name: String) -> String {
        name.count > maxNameLength ? String(name.prefix(maxNameLength - 1)) + "…" : name
    }

    /// Farbpunkt als nicht-Template-Bild, denn die Menüleiste färbt SwiftUI-Formen sonst einfarbig.
    static func dot(hex: String) -> NSImage {
        let color = NSColor(Color(hex: hex))
        let image = NSImage(size: NSSize(width: 9, height: 9), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
