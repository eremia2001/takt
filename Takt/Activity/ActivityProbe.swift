import AppKit
import ApplicationServices
import Foundation

/// Eine Beobachtung der vordersten App: was gerade im Vordergrund ist, samt Fenstertitel und
/// Repository, soweit ermittelbar.
struct ActivityObservation: Sendable, Equatable {
    var bundleID: String
    var appName: String?
    /// Titel des fokussierten Fensters; nur mit Bedienungshilfen-Freigabe.
    var windowTitle: String?
    /// `kAXDocumentAttribute` des Fensters als Pfad (Xcode: Datei, Terminal: Arbeitsordner).
    var documentPath: String?
    /// Normalisierter Repository-Ordner (`~` aufgelöst, ohne `/` am Ende).
    var repoPath: String?
    /// Ob die Bedienungshilfen-Freigabe bei dieser Beobachtung vorlag.
    var isTrusted: Bool
}

/// Liest Fenstertitel und Dokument per Accessibility. Läuft abseits des Main-Threads; jede
/// Abfrage hat ein kurzes Zeitlimit, damit eine hängende App nichts blockiert.
enum ActivityProbe {
    /// Zeitlimit je Accessibility-Abfrage.
    static let messagingTimeout: Float = 0.5

    /// Ob Takt die Bedienungshilfen-Freigabe hat (ohne Systemabfrage).
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Fragt die Freigabe an (Systemdialog, trägt Takt in die Liste ein) und öffnet
    /// Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen.
    @MainActor
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Beobachtet die App mit `pid`. Ohne Freigabe bleibt es bei der Bundle-ID.
    static func observe(
        pid: pid_t,
        bundleID: String,
        appName: String?,
        index: RepoIndex,
        fileManager: FileManager = .default
    ) -> ActivityObservation {
        let trusted = AXIsProcessTrusted()
        var observation = ActivityObservation(bundleID: bundleID, appName: appName, isTrusted: trusted)
        guard trusted else { return observation }
        let window = focusedWindow(pid: pid)
        observation.windowTitle = window.title
        observation.documentPath = window.document.flatMap(ActivityHeuristics.documentURLPath)
        observation.repoPath = ActivityHeuristics.detectRepo(
            bundleID: bundleID,
            windowTitle: window.title,
            documentPath: observation.documentPath,
            index: index,
            fileManager: fileManager
        )
        return observation
    }

    /// Titel und Dokument des fokussierten (ersatzweise des Haupt-)Fensters.
    static func focusedWindow(pid: pid_t) -> (title: String?, document: String?) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        guard let window = element(app, kAXFocusedWindowAttribute) ?? element(app, kAXMainWindowAttribute) else {
            return (nil, nil)
        }
        AXUIElementSetMessagingTimeout(window, messagingTimeout)
        let title = string(window, kAXTitleAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let document = string(window, kAXDocumentAttribute)
        return ((title?.isEmpty ?? true) ? nil : title, document)
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else {
            return nil
        }
        if let text = value as? String { return text }
        if let url = value as? URL { return url.absoluteString }
        return nil
    }
}

/// Anzeigenamen von Apps zur Bundle-ID (laufende App, sonst Programmordner), zwischengespeichert.
@MainActor
enum ActivityAppNames {
    private static var cache: [String: String] = [:]

    static func name(for bundleID: String) -> String {
        if let cached = cache[bundleID] { return cached }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
            FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "")
        }
        let name = running ?? installed ?? bundleID
        cache[bundleID] = name
        return name
    }

    static func remember(_ name: String?, for bundleID: String) {
        guard let name, !name.isEmpty else { return }
        cache[bundleID] = name
    }
}
