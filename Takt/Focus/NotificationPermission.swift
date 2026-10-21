import AppKit
import Foundation
import os
import UserNotifications

/// Systemstatus der Mitteilungen für die Einstellungen (vereinfacht aus `UNAuthorizationStatus`).
enum NotificationPermissionStatus: Equatable, Sendable {
    /// Erlaubt (auch vorläufig). `showsAlerts == false`: Hinweisstil „Keine“ – Mitteilungen landen
    /// nur in der Mitteilungszentrale.
    case allowed(showsAlerts: Bool)
    case denied
    case notDetermined
}

/// Ergebnis von „Testmitteilung senden“.
enum NotificationTestResult: Equatable, Sendable {
    case sent(Date)
    case notAllowed
    case failed(String)
}

/// Berechtigung abfragen/anfordern, Systemeinstellungen öffnen und Testmitteilung senden.
/// Getrennt von der Oberfläche, damit sich der Reiter „Mitteilungen“ ohne App-Bundle rendern lässt.
@MainActor
enum NotificationPermission {
    private static let logger = Logger(subsystem: "dev.eremiya.takt", category: "focus")
    private static let testIdentifier = "dev.eremiya.takt.test"
    /// Bereich „Mitteilungen“ in den Systemeinstellungen.
    static let systemSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!

    static func status(center: UNUserNotificationCenter = .current()) async -> NotificationPermissionStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        default:
            // .authorized, .provisional (und .ephemeral, auf macOS ungenutzt).
            return .allowed(showsAlerts: settings.alertStyle != .none)
        }
    }

    /// Fragt nach der Erlaubnis (nur solange nicht entschieden) und liefert den neuen Status.
    static func request(center: UNUserNotificationCenter = .current()) async -> NotificationPermissionStatus {
        await NotificationCategories.requestAuthorizationIfNeeded(center: center)
        return await status(center: center)
    }

    static func openSystemSettings() {
        NSWorkspace.shared.open(systemSettingsURL)
    }

    /// Stellt sofort eine Testmitteilung zu. Läuft über das Gate (Art `.test`: ignoriert Ruhezeiten).
    static func sendTest(
        settings: some NotificationGateSettings,
        center: UNUserNotificationCenter = .current()
    ) async -> NotificationTestResult {
        guard NotificationGate.allows(kind: .test, settings: settings) else { return .notAllowed }
        let status = await request(center: center)
        guard case .allowed = status else { return .notAllowed }

        let content = UNMutableNotificationContent()
        content.title = "Takt: Testmitteilung"
        content.body = "So sehen Mitteilungen von Takt aus. Wenn du das liest, kommt alles an."
        content.sound = .default
        let request = UNNotificationRequest(identifier: testIdentifier, content: content, trigger: nil)
        do {
            try await center.add(request)
            logger.info("Testmitteilung zugestellt.")
            return .sent(.now)
        } catch {
            logger.error("Testmitteilung nicht zugestellt: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }
}
