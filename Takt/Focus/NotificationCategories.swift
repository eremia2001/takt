import Foundation
import os
import UserNotifications

/// Kennungen und Kategorien aller Takt-Mitteilungen an einer Stelle.
///
/// `UNUserNotificationCenter.setNotificationCategories` ersetzt immer den gesamten Satz. Früher
/// registrierten `BreakReminder` und `ForgottenTimerGuard` ihre Kategorien getrennt per
/// Lesen-und-Ergänzen; liefen beide gleichzeitig, ging eine verloren. Jetzt registriert
/// `register()` alle Kategorien in einem Rutsch, einmal beim App-Start (`TaktApp`).
enum NotificationCategories {
    /// Pausenerinnerung „Kurze Pause?“ (ohne Aktionen).
    enum Break {
        static let category = "dev.eremiya.takt.break-reminder"
    }

    /// Geplanter Block „Geplant: Kundenportal um 14:00“.
    enum Planned {
        static let category = "dev.eremiya.takt.planned-block"
        static let start = "planned.start"
    }

    /// Nachfrage bei vergessenem Timer.
    enum ForgottenTimer {
        static let category = "dev.eremiya.takt.forgotten-timer"
        static let keepRunning = "forgotten.keep-running"
        static let stopNow = "forgotten.stop-now"
        static let stopAt = "forgotten.stop-at"
    }

    /// Leerlauf erkannt („klicken zum Entscheiden“).
    enum Idle {
        static let category = "dev.eremiya.takt.idle"
        static let subtract = "idle.subtract"
        static let keep = "idle.keep"
    }

    /// Pomodoro: Ende der Pause mit „Weiter“.
    enum PomodoroBreakOver {
        static let category = "dev.eremiya.takt.pomodoro-break-over"
        static let resume = "pomodoro.resume"
    }

    private static let logger = Logger(subsystem: "dev.eremiya.takt", category: "focus")

    /// Registriert alle Kategorien auf einmal (ersetzt einen älteren Satz vollständig).
    static func register(center: UNUserNotificationCenter = .current()) {
        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: Break.category, actions: [], intentIdentifiers: []),
            UNNotificationCategory(
                identifier: Planned.category,
                actions: [UNNotificationAction(identifier: Planned.start, title: "Starten")],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: ForgottenTimer.category,
                actions: [
                    UNNotificationAction(identifier: ForgottenTimer.keepRunning, title: "Läuft weiter"),
                    UNNotificationAction(identifier: ForgottenTimer.stopNow, title: "Jetzt stoppen"),
                    UNNotificationAction(identifier: ForgottenTimer.stopAt, title: "Stoppen um …", options: [.foreground]),
                ],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: Idle.category,
                actions: [
                    UNNotificationAction(identifier: Idle.subtract, title: "Abziehen"),
                    UNNotificationAction(identifier: Idle.keep, title: "Behalten"),
                ],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: PomodoroBreakOver.category,
                actions: [UNNotificationAction(identifier: PomodoroBreakOver.resume, title: "Weiter")],
                intentIdentifiers: []
            ),
        ]
        center.setNotificationCategories(categories)
        logger.info("Mitteilungs-Kategorien registriert (\(categories.count)).")
    }

    /// Fragt einmalig nach der Erlaubnis für Mitteilungen, solange noch nicht entschieden.
    static func requestAuthorizationIfNeeded(center: UNUserNotificationCenter = .current()) async {
        let status = await center.notificationSettings().authorizationStatus
        guard status == .notDetermined else { return }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            logger.info("Mitteilungen \(granted ? "erlaubt" : "abgelehnt", privacy: .public).")
        } catch {
            logger.error("Mitteilungs-Berechtigung fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stellt eine Mitteilung sofort zu (gleiche Kennung ersetzt eine ältere).
    static func deliverNow(
        identifier: String,
        content: UNNotificationContent,
        center: UNUserNotificationCenter = .current()
    ) {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        Task {
            await requestAuthorizationIfNeeded(center: center)
            do {
                try await center.add(request)
            } catch {
                logger.error("Mitteilung \(identifier, privacy: .public) nicht zugestellt: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Entfernt eine zugestellte oder noch geplante Mitteilung.
    static func remove(identifier: String, center: UNUserNotificationCenter = .current()) {
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
