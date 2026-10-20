import AppKit
import SwiftUI

/// Kurze, leise Rückmeldung auf den globalen Kurzbefehl: eine kleine Kapsel unten mittig,
/// 1,5 s sichtbar. Nicht aktivierend (die vordere App behält den Fokus) und klick-durchlässig.
@MainActor
final class HotKeyOverlay {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    /// Sichtbare Dauer ohne Ein- und Ausblenden.
    private static let visibleDuration: Duration = .milliseconds(1500)

    func show(_ message: HotKeyOverlayMessage) {
        let panel = panel ?? makePanel()
        self.panel = panel

        let hosting = NSHostingView(rootView: HotKeyOverlayView(message: message))
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        panel.contentView = hosting
        panel.setContentSize(size)
        position(panel, size: size)

        hideTask?.cancel()
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }

        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleDuration)
            guard !Task.isCancelled else { return }
            self?.fadeOut()
        }
    }

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Inzwischen neu eingeblendet? Dann sichtbar lassen.
                guard let self, self.hideTask?.isCancelled == false, panel.alphaValue == 0 else { return }
                panel.orderOut(nil)
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    /// Unten mittig auf dem Bildschirm mit dem Mauszeiger (dort schaut der Nutzer meist hin).
    private func position(_ panel: NSPanel, size: NSSize) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 96)
        panel.setFrameOrigin(origin)
    }
}

/// Inhalt der Rückmeldung.
struct HotKeyOverlayMessage {
    enum Kind { case started, stopped, info }

    var kind: Kind
    var text: String
    /// Projektfarbe als `#RRGGBB` (für das Symbol), optional.
    var colorHex: String?
}

/// Kapsel mit Symbol und Text, Materialhintergrund wie Systemeinblendungen.
struct HotKeyOverlayView: View {
    let message: HotKeyOverlayMessage

    private var color: Color { message.colorHex.map { Color(hex: $0) } ?? .secondary }

    var body: some View {
        HStack(spacing: 9) {
            switch message.kind {
            case .started:
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
            case .stopped:
                StopGlyph(color: color, size: 10)
            case .info:
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(message.text)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .padding(1)
        .fixedSize()
    }
}
