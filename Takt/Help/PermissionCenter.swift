import AppKit
import ApplicationServices
import Carbon
import EventKit
import Observation
import SwiftUI

/// Liest und erfragt die Freigaben über die vorhandenen Stellen: `NotificationPermission`,
/// `CalendarService` (falls vorhanden, sonst EventKit direkt), `ActivityProbe` und – für Automation –
/// `AEDeterminePermissionToAutomateTarget` (Spotify und Musik).
/// Liest neu, sobald Takt wieder aktiv wird (Rückkehr aus den Systemeinstellungen).
@MainActor
@Observable
final class PermissionCenter {
    private(set) var states: [PermissionKind: PermissionState] = Dictionary(
        uniqueKeysWithValues: PermissionKind.allCases.map { ($0, PermissionState.checking) }
    )

    @ObservationIgnored private weak var calendarService: CalendarService?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    /// Apps, die Takt per Apple Events steuert.
    private struct AutomationTarget {
        let name: String
        let bundleID: String
    }

    private static let automationTargets = [
        AutomationTarget(name: "Spotify", bundleID: "com.spotify.client"),
        AutomationTarget(name: "Musik", bundleID: "com.apple.Music"),
    ]

    init(calendarService: CalendarService? = nil) {
        self.calendarService = calendarService
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    deinit {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }

    func state(_ kind: PermissionKind) -> PermissionState {
        states[kind] ?? .checking
    }

    // MARK: Lesen

    func refresh() {
        states[.calendar] = Self.calendarState()
        states[.accessibility] = ActivityProbe.isTrusted
            ? .granted()
            : .notDetermined("Nicht erlaubt")
        Task {
            states[.notifications] = Self.notificationState(await NotificationPermission.status())
            states[.automation] = await Self.automationState()
        }
    }

    private static func notificationState(_ status: NotificationPermissionStatus) -> PermissionState {
        switch status {
        case .allowed(let showsAlerts): showsAlerts ? .granted() : .limited("Erlaubt, aber ohne Banner")
        case .denied: .denied()
        case .notDetermined: .notDetermined()
        }
    }

    private static func calendarState() -> PermissionState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted()
        case .notDetermined: .notDetermined()
        case .denied: .denied()
        case .restricted: .denied("Vom System eingeschränkt")
        case .writeOnly: .limited("Nur Schreibzugriff")
        @unknown default: .notDetermined("Unbekannt")
        }
    }

    /// Zusammengefasster Status für Spotify und Musik: erlaubt, sobald eine installierte App erlaubt
    /// ist; abgelehnt nur, wenn keine erlaubt und mindestens eine abgelehnt ist.
    private static func automationState() async -> PermissionState {
        let installed = automationTargets.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil
        }
        guard !installed.isEmpty else { return .limited("Weder Spotify noch Musik gefunden") }
        var granted: [String] = []
        var denied: [String] = []
        var notRunning: [String] = []
        for target in installed {
            let bundleID = target.bundleID
            let status = await Task.detached { automationStatus(bundleID: bundleID, ask: false) }.value
            switch status {
            case noErr: granted.append(target.name)
            case OSStatus(errAEEventNotPermitted): denied.append(target.name)
            case OSStatus(procNotFound): notRunning.append(target.name)
            default: break // noch nicht gefragt
            }
        }
        if !granted.isEmpty { return .granted("Erlaubt: " + granted.joined(separator: ", ")) }
        if !denied.isEmpty { return .denied("Abgelehnt: " + denied.joined(separator: ", ")) }
        // macOS verrät den Status nur, solange die App läuft.
        if notRunning.count == installed.count {
            return .notDetermined("Unbekannt – " + notRunning.joined(separator: " und ") + " läuft nicht")
        }
        return .notDetermined("Noch nicht gefragt")
    }

    /// `AEDeterminePermissionToAutomateTarget` für eine App. `ask == true` zeigt die Abfrage von
    /// macOS und blockiert bis zur Antwort – deshalb nie auf dem Main-Thread aufrufen.
    nonisolated private static func automationStatus(bundleID: String, ask: Bool) -> OSStatus {
        var target = AEAddressDesc()
        let bytes = Array(bundleID.utf8)
        let created = bytes.withUnsafeBufferPointer { buffer in
            AECreateDesc(DescType(typeApplicationBundleID), buffer.baseAddress, buffer.count, &target)
        }
        guard created == noErr else { return OSStatus(created) }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
    }

    // MARK: Erfragen

    func request(_ kind: PermissionKind) {
        switch kind {
        case .notifications:
            states[.notifications] = .checking
            Task {
                let status = await NotificationPermission.request()
                states[.notifications] = Self.notificationState(status)
            }
        case .calendar:
            states[.calendar] = .checking
            Task {
                if let calendarService {
                    await calendarService.requestAccess()
                } else {
                    _ = try? await EKEventStore().requestFullAccessToEvents()
                }
                states[.calendar] = Self.calendarState()
            }
        case .accessibility:
            ActivityProbe.requestTrust()
        case .automation:
            requestAutomation()
        }
    }

    /// Fragt für Spotify und Musik (soweit installiert). Die Abfrage braucht eine laufende App;
    /// läuft sie nicht, startet Takt sie unauffällig im Hintergrund.
    private func requestAutomation() {
        states[.automation] = .checking
        let targets = Self.automationTargets.compactMap { target -> (AutomationTarget, URL)? in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleID).map { (target, $0) }
        }
        Task {
            for (target, url) in targets {
                let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).isEmpty
                if !isRunning {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = false
                    configuration.hides = true
                    _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                    try? await Task.sleep(for: .seconds(1.5))
                }
                let bundleID = target.bundleID
                _ = await Task.detached { Self.automationStatus(bundleID: bundleID, ask: true) }.value
            }
            states[.automation] = await Self.automationState()
        }
    }

    func openSystemSettings(_ kind: PermissionKind) {
        let anchor: String
        switch kind {
        case .notifications:
            NotificationPermission.openSystemSettings()
            return
        case .automation: anchor = "Privacy_Automation"
        case .calendar: anchor = "Privacy_Calendars"
        case .accessibility: anchor = "Privacy_Accessibility"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension PermissionList {
    /// Mit einer `PermissionCenter` verbunden.
    init(center: PermissionCenter, kinds: [PermissionKind] = PermissionKind.allCases) {
        self.init(
            kinds: kinds,
            state: { center.state($0) },
            request: { center.request($0) },
            openSettings: { center.openSystemSettings($0) }
        )
    }
}
