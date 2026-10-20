import AppKit
import Observation
import SwiftUI
import TaktCore

/// Steuert alles rund um Menüleiste und globalen Kurzbefehl:
/// Minutentakt für die Anzeige in der Menüleiste, Dock-Symbol (Aktivierungsrichtlinie),
/// Anmeldung des Kurzbefehls und die Start/Stopp-Aktion samt kurzer Einblendung.
@MainActor
@Observable
final class MenuBarController {
    /// Aktuelle Minute; treibt die Dauer in der Menüleiste (minütlich, keine Sekunden).
    private(set) var now = Date.now
    /// Während das Aufnahmefeld in den Einstellungen Tasten liest, ist der Kurzbefehl abgemeldet –
    /// sonst würde die alte Kombination beim erneuten Drücken sofort auslösen.
    var isRecordingShortcut = false
    /// Hinweis für die Einstellungen, wenn macOS den Kurzbefehl ablehnt (z. B. schon belegt).
    private(set) var shortcutProblem: String?

    @ObservationIgnored private let store: TaktStore
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let hotKey = GlobalHotKey()
    @ObservationIgnored private let overlay = HotKeyOverlay()
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var launchObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var didFinishLaunching = false

    init(store: TaktStore, settings: AppSettings) {
        self.store = store
        self.settings = settings

        hotKey.action = { [weak self] in self?.toggleTimerFromShortcut() }
        startClock()

        let center = NotificationCenter.default
        // Dock-Symbol vor dem ersten Fenster festlegen, damit es beim Start nicht kurz aufblitzt.
        launchObservers.append(center.addObserver(
            forName: NSApplication.willFinishLaunchingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyActivationPolicy() }
        })
        launchObservers.append(center.addObserver(
            forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.didFinishLaunching = true
                self.observeSettings()
            }
        })
        // Nach dem Aufwachen aus dem Ruhezustand stimmt die Minute sonst bis zum nächsten Takt nicht.
        launchObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = .now }
        })
    }

    // MARK: Timer-Aktionen

    /// Start aus der Menüleiste (laufender Timer eines anderen Projekts wird dabei beendet).
    func start(_ projectId: UUID) {
        guard store.running?.project.id != projectId else { return }
        store.start(projectId: projectId)
        now = .now
    }

    /// Stopp aus der Menüleiste: direkt, ohne Notiz „Nächster Schritt“.
    func stop() {
        store.stop(nextStep: nil)
        now = .now
    }

    /// Globaler Kurzbefehl: läuft etwas → stoppen, sonst das zuletzt genutzte Projekt starten.
    func toggleTimerFromShortcut() {
        store.refresh()
        let date = Date.now
        if let running = store.running {
            let duration = running.entry.duration(at: date)
            if store.stop(nextStep: nil) {
                overlay.show(HotKeyOverlayMessage(
                    kind: .stopped,
                    text: "\(running.project.name) gestoppt · \(DurationFormat.hourMinute(duration))",
                    colorHex: running.project.colorHex
                ))
            } else {
                overlay.show(HotKeyOverlayMessage(kind: .info, text: "Stoppen fehlgeschlagen"))
            }
        } else if let project = store.lastUsedProject ?? store.projects.first {
            if store.start(projectId: project.id) {
                overlay.show(HotKeyOverlayMessage(
                    kind: .started,
                    text: "\(project.name) gestartet",
                    colorHex: project.colorHex
                ))
            } else {
                overlay.show(HotKeyOverlayMessage(kind: .info, text: "Starten fehlgeschlagen"))
            }
        } else {
            overlay.show(HotKeyOverlayMessage(kind: .info, text: "Noch kein Projekt angelegt"))
        }
        now = .now
    }

    /// Kurze Einblendung wie beim Kurzbefehl, z. B. „Pause vorbei“ vom Pomodoro.
    func showOverlay(_ message: HotKeyOverlayMessage, visibleFor duration: Duration = HotKeyOverlay.visibleDuration) {
        overlay.show(message, visibleFor: duration)
    }

    // MARK: Fenster

    /// Holt das Hauptfenster nach vorn. `openWindow` öffnet es neu, falls es geschlossen wurde.
    /// Funktioniert auch ohne Dock-Symbol (`.accessory`), weil die App ausdrücklich aktiviert wird.
    func showMainWindow(openWindow: OpenWindowAction?) {
        NSApp.activate()
        if let window = Self.mainWindow() {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        } else if let openWindow {
            openWindow(id: Self.mainWindowId)
            // Das neue Fenster entsteht erst im nächsten Durchlauf; dann nach vorn holen.
            DispatchQueue.main.async {
                NSApp.activate()
                Self.mainWindow()?.makeKeyAndOrderFront(nil)
            }
        } else {
            Self.openTodayViaURL()
        }
    }

    /// Hauptfenster mit dem Bereich „Heute“ zeigen (z. B. um ein Ende zu korrigieren).
    /// Läuft über die eigene URL `takt://today`, weil nur das Hauptfenster selbst den Bereich
    /// umschalten kann; ist kein Fenster offen, legt SwiftUI dabei eines an.
    static func showToday() {
        NSApp.activate()
        openTodayViaURL()
    }

    /// Kennung der Hauptfenster-Szene (`WindowGroup(id:)` in `TaktApp`).
    static let mainWindowId = "main"

    private static func openTodayViaURL() {
        guard let url = URL(string: "takt://today") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // Ausdrücklich diese App: Ein zweites installiertes Takt könnte sonst die URL bekommen.
        NSWorkspace.shared.open([url], withApplicationAt: Bundle.main.bundleURL, configuration: configuration)
    }

    /// Das sichtbare oder minimierte Hauptfenster (nicht Einstellungen, nicht Menüleisten-Fenster).
    static func mainWindow() -> NSWindow? {
        let candidates = NSApp.windows.filter { window in
            !(window is NSPanel)
                && window.canBecomeMain
                && (window.isVisible || window.isMiniaturized)
                && window.identifier?.rawValue.contains("Settings") != true
        }
        return candidates.first { $0.identifier?.rawValue.hasPrefix(mainWindowId) == true } ?? candidates.first
    }

    // MARK: Einstellungen anwenden

    private func observeSettings() {
        observeContinuously { [weak self] in self?.applyActivationPolicy() }
        observeContinuously { [weak self] in self?.updateHotKey() }
    }

    /// Dock-Symbol ausblenden nur zusammen mit der Menüleiste – sonst wäre die App
    /// (außer über das Widget) nicht mehr erreichbar.
    private func applyActivationPolicy() {
        let accessory = settings.hideDockIcon && settings.menuBarEnabled
        let target: NSApplication.ActivationPolicy = accessory ? .accessory : .regular
        guard NSApp.activationPolicy() != target else { return }
        let keyWindow = NSApp.keyWindow
        NSApp.setActivationPolicy(target)
        guard didFinishLaunching else { return }
        // Beim Wechsel verliert die App kurz den Fokus (und bei `.regular` fehlt sonst die
        // Menüzeile); das Fenster, in dem umgeschaltet wurde, bleibt vorn.
        DispatchQueue.main.async {
            NSApp.activate()
            keyWindow?.makeKeyAndOrderFront(nil)
        }
    }

    private func updateHotKey() {
        let enabled = settings.globalShortcutEnabled
        let combo = KeyCombo(
            keyCode: settings.globalShortcutKeyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: settings.globalShortcutModifiers)
        )
        guard enabled, !isRecordingShortcut else {
            hotKey.unregister()
            if !enabled { shortcutProblem = nil }
            return
        }
        if hotKey.register(keyCode: combo.keyCode, modifiers: combo.modifiers) {
            shortcutProblem = nil
        } else {
            shortcutProblem = "\(combo.display) ist bereits von einer anderen App belegt."
        }
    }

    // MARK: Minutentakt

    /// Tickt jeweils zur vollen Minute (wie die Timeline des Widgets).
    private func startClock() {
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                let date = Date.now
                let next = (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60 + 60
                let delay = max(1, next - date.timeIntervalSinceReferenceDate + 0.05)
                try? await Task.sleep(for: .seconds(delay))
                guard let self else { return }
                self.now = .now
            }
        }
    }
}
