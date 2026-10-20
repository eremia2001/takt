import AppKit
import SwiftUI

// Schwebendes Schnelleingabe-Fenster (Spotlight-artig), per Kurzbefehl (Standard ⌃⌥⌘N) oder
// aus dem Menüleisten-Popover. Ein `NSPanel`, das Tastaturfokus bekommt, ohne die App zu
// aktivieren: Die vordere App bleibt vorn, nach Enter/Esc geht es dort direkt weiter.

/// Inhalt des Fensters: großes Feld, darunter Vorschau/Fehler/Kapseln. Rein darstellend.
struct QuickEntryPanelView: View {
    let handlers: QuickEntryHandlers
    var shortcut: String?
    var onSuccess: (QuickEntrySuccess) -> Void = { _ in }
    var onCancel: () -> Void = {}
    var initialText = ""
    var focusOnAppear = true

    @Environment(\.colorScheme) private var scheme

    static let width: CGFloat = 560

    var body: some View {
        let theme = DesignTheme(scheme: scheme)
        QuickEntryField(
            size: .large,
            theme: theme,
            handlers: handlers,
            initialText: initialText,
            onSuccess: onSuccess,
            onCancel: onCancel,
            panelShortcut: shortcut,
            focusOnAppear: focusOnAppear
        )
        .frame(width: Self.width)
        .background(.regularMaterial)
        .background(theme.window.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.16 : 0.08), lineWidth: 1)
        )
    }
}

/// Randloses Panel, das trotzdem Key werden darf (sonst bekäme das Textfeld keine Tasten).
private final class QuickEntryNSPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class QuickEntryPanelController: NSObject, NSWindowDelegate {
    private var panel: QuickEntryNSPanel?
    private let handlers: () -> QuickEntryHandlers
    private let shortcut: () -> String?
    private let onSuccess: (QuickEntrySuccess) -> Void

    /// `handlers` und `shortcut` werden bei jedem Öffnen frisch gelesen.
    init(handlers: @escaping () -> QuickEntryHandlers,
         shortcut: @escaping () -> String?,
         onSuccess: @escaping (QuickEntrySuccess) -> Void) {
        self.handlers = handlers
        self.shortcut = shortcut
        self.onSuccess = onSuccess
    }

    var isVisible: Bool { panel?.isVisible == true }

    /// Öffnet das Fenster; ist es schon offen, schließt der Kurzbefehl es wieder.
    func toggle() {
        if isVisible { close() } else { show() }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        // Bei jedem Öffnen neue Ansicht: leeres Feld, frischer Fokus.
        let view = QuickEntryPanelView(
            handlers: handlers(),
            shortcut: shortcut(),
            onSuccess: { [weak self] success in
                self?.close()
                self?.onSuccess(success)
            },
            onCancel: { [weak self] in self?.close() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        panel.setContentSize(size)
        position(panel, size: size)

        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        // Ansicht verwerfen, damit kein Text bis zum nächsten Öffnen stehen bleibt.
        panel.contentView = nil
    }

    // MARK: NSWindowDelegate

    /// Klick in eine andere App oder ein anderes Fenster: schließen wie Spotlight.
    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    // MARK: Interna

    private func makePanel() -> QuickEntryNSPanel {
        let panel = QuickEntryNSPanel(
            contentRect: NSRect(x: 0, y: 0, width: QuickEntryPanelView.width, height: 100),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.becomesKeyOnlyIfNeeded = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.delegate = self
        return panel
    }

    /// Mittig im oberen Drittel des Bildschirms mit dem Mauszeiger (wie Spotlight).
    private func position(_ panel: NSPanel, size: NSSize) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let top = frame.maxY - frame.height * 0.22
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: top - size.height))
    }
}
