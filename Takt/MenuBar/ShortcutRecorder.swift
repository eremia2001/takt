import AppKit
import SwiftUI

/// Aufnahmefeld für den globalen Kurzbefehl: Klick → „Tasten drücken…“, die nächste
/// Tastenkombination mit ⌃, ⌥ oder ⌘ wird übernommen. Esc bricht ab.
/// Während der Aufnahme ist der bisherige Kurzbefehl abgemeldet (`isRecording`).
struct ShortcutRecorder: View {
    let combo: KeyCombo
    @Binding var isRecording: Bool
    let onRecord: (KeyCombo) -> Void

    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? "Tasten drücken…" : combo.display)
                    .font(.system(size: 13, weight: isRecording ? .regular : .medium))
                    .monospacedDigit()
                    .foregroundStyle(isRecording ? .secondary : .primary)
                    .frame(minWidth: 110)
                    .frame(height: 24)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                                    lineWidth: isRecording ? 2 : 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isRecording ? "Esc bricht ab" : "Klicken und neue Tastenkombination drücken")
            .accessibilityLabel(isRecording ? "Kurzbefehl aufnehmen, Tasten drücken" : "Kurzbefehl \(combo.display)")

            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        hint = nil
        isRecording = true
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    /// Gibt `nil` zurück, damit der Tastendruck nicht zusätzlich im Fenster landet.
    private func handle(_ event: NSEvent) -> NSEvent? {
        let candidate = KeyCombo(keyCode: Int(event.keyCode), modifiers: event.modifierFlags)
        if candidate.modifiers.isEmpty && event.keyCode == 53 {  // Esc
            hint = nil
            stopRecording()
            return nil
        }
        guard candidate.hasRequiredModifier else {
            hint = "Bitte mit ⌃, ⌥ oder ⌘ kombinieren."
            return nil
        }
        hint = nil
        onRecord(candidate)
        stopRecording()
        return nil
    }
}
