import AppKit
import Carbon.HIToolbox
import os

/// Systemweiter Kurzbefehl über Carbon `RegisterEventHotKey` – ohne Drittbibliothek und ohne
/// Bedienungshilfen-Berechtigung. Es gibt genau einen Kurzbefehl; `register` ersetzt ihn.
@MainActor
final class GlobalHotKey {
    /// Wird auf dem Main-Thread aufgerufen, sobald der Kurzbefehl gedrückt wurde.
    var action: () -> Void = {}

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Kennung des Kurzbefehls („TAKT“ als Vierzeichen-Code), damit fremde Ereignisse nicht zählen.
    private static let signature: OSType = 0x5441_4B54
    private static let hotKeyId: UInt32 = 1
    private static let logger = Logger(subsystem: "dev.eremiya.takt", category: "hotkey")

    /// Ob gerade ein Kurzbefehl angemeldet ist.
    var isRegistered: Bool { hotKeyRef != nil }

    /// Meldet den Kurzbefehl (neu) an. Gibt `false` zurück, wenn macOS ihn ablehnt –
    /// meist, weil eine andere App dieselbe Kombination belegt.
    @discardableResult
    func register(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> Bool {
        unregister()
        installHandlerIfNeeded()

        let id = EventHotKeyID(signature: Self.signature, id: Self.hotKeyId)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            Self.carbonModifiers(modifiers),
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            Self.logger.error("Kurzbefehl nicht angemeldet (Status \(status, privacy: .public)).")
            return false
        }
        hotKeyRef = ref
        Self.logger.info("Kurzbefehl \(KeyCombo(keyCode: keyCode, modifiers: modifiers).display, privacy: .public) angemeldet.")
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }

    // MARK: Interna

    /// Der Ereignis-Handler bleibt für die gesamte Laufzeit installiert; nur der Kurzbefehl
    /// selbst wird bei Änderungen ab- und wieder angemeldet.
    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context -> OSStatus in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &id
                )
                guard result == noErr, id.signature == GlobalHotKey.signature, id.id == GlobalHotKey.hotKeyId else {
                    return OSStatus(eventNotHandledErr)
                }
                // Carbon ruft auf dem Main-Thread (Ereignisschleife der App) auf.
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1,
            &eventType,
            context,
            &handlerRef
        )
        if status != noErr {
            Self.logger.error("Ereignis-Handler nicht installiert (Status \(status, privacy: .public)).")
        }
    }

    /// `NSEvent.ModifierFlags` → Carbon-Modifikatoren.
    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}

/// Tastenkombination aus virtuellem Tastencode und Modifikatoren, mit Anzeige als Symbolfolge.
struct KeyCombo: Equatable {
    var keyCode: Int
    var modifiers: NSEvent.ModifierFlags

    /// Nur die für Kurzbefehle relevanten Modifikatoren.
    static let relevantModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    init(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevantModifiers)
    }

    /// Ein Kurzbefehl braucht mindestens ⌃, ⌥ oder ⌘ – ⇧ allein würde normales Tippen abfangen.
    var hasRequiredModifier: Bool {
        !modifiers.intersection([.control, .option, .command]).isEmpty
    }

    /// z. B. „⌃⌥⌘T“ – Reihenfolge wie im macOS-Menü.
    var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    /// Anzeigename einer Taste: Sondertasten als Symbol, sonst das Zeichen der aktuellen
    /// Tastaturbelegung (deutsche Belegung: Tastencode 16 ergibt „Z“).
    static func keyName(_ keyCode: Int) -> String {
        if let special = specialKeys[keyCode] { return special }
        return character(for: keyCode)?.uppercased() ?? "#\(keyCode)"
    }

    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Leertaste", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        kVK_ANSI_KeypadEnter: "⌤",
    ]

    /// Zeichen der Taste ohne Modifikatoren in der aktuellen Tastaturbelegung.
    private static func character(for keyCode: Int) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
                ?? TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
            guard status == noErr, length > 0 else { return nil }
            let text = String(utf16CodeUnits: chars, count: length)
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        }
    }
}
