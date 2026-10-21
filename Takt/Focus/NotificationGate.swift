import Foundation
import os

/// Alle Arten von Takt-Mitteilungen (Systemmitteilungen über `UNUserNotificationCenter`).
/// Der Termin-Hinweis in „Heute“ ist keine Mitteilung und fehlt hier.
enum NotificationKind: String, CaseIterable, Sendable {
    case breakReminder
    case pomodoro
    case idle
    case forgottenTimer
    case budget
    case activity
    case plannedBlock
    /// Knopf „Testmitteilung senden“ in den Einstellungen.
    case test

    /// Name für Logs und Oberfläche.
    var title: String {
        switch self {
        case .breakReminder: "Pausenerinnerung"
        case .pomodoro: "Pomodoro"
        case .idle: "Leerlauf"
        case .forgottenTimer: "Vergessener Timer"
        case .budget: "Budget"
        case .activity: "Aktivität"
        case .plannedBlock: "Geplanter Block"
        case .test: "Testmitteilung"
        }
    }

    /// Kommt auch in Ruhezeiten und am Wochenende: Ein vergessener Timer kostet sonst echte Stunden,
    /// und die Testmitteilung soll zeigen, ob überhaupt etwas ankommt.
    var ignoresQuietHours: Bool {
        self == .forgottenTimer || self == .test
    }
}

/// Was das Gate über eine Mitteilung braucht. `AppSettings` erfüllt es; das Protokoll erlaubt
/// Tests ohne `UserDefaults` und ohne den Rest der App.
@MainActor
protocol NotificationGateSettings: AnyObject {
    var breakReminderEnabled: Bool { get }
    var pomodoroNotificationsEnabled: Bool { get }
    var idleDetectionEnabled: Bool { get }
    var forgottenTimerEnabled: Bool { get }
    var budgetWarningsEnabled: Bool { get }
    var activityNotificationsEnabled: Bool { get }
    var calendarPlannedBlockNotificationEnabled: Bool { get }
    var notificationsQuietHoursEnabled: Bool { get }
    /// Minuten seit Mitternacht.
    var quietHoursStart: Int { get }
    /// Minuten seit Mitternacht; kleiner als `quietHoursStart` = über Mitternacht.
    var quietHoursEnd: Int { get }
    var notificationsWeekendQuiet: Bool { get }
}

/// Entscheidet vor jedem `UNUserNotificationCenter.add`, ob eine Mitteilung kommen darf:
/// Schalter der Art, Ruhezeiten und „Am Wochenende still“. Unterdrücktes wird geloggt
/// (Kategorie `focus`).
enum NotificationGate {
    enum Verdict: Equatable, Sendable {
        case allowed
        /// Schalter der Art ist aus.
        case disabled
        /// Innerhalb der täglichen Ruhezeit.
        case quietHours
        /// Samstag oder Sonntag mit „Am Wochenende still“.
        case weekend
    }

    private static let logger = Logger(subsystem: "dev.eremiya.takt", category: "focus")

    /// `true`, wenn die Mitteilung `kind` zum Zeitpunkt `now` zugestellt werden darf. Für geplante
    /// Mitteilungen ist `now` der Auslösezeitpunkt. Unterdrückte Mitteilungen werden geloggt.
    @MainActor
    static func allows(
        kind: NotificationKind,
        now: Date = .now,
        settings: some NotificationGateSettings,
        calendar: Calendar = .current
    ) -> Bool {
        let verdict = verdict(kind: kind, now: now, settings: settings, calendar: calendar)
        switch verdict {
        case .allowed:
            return true
        case .disabled:
            logger.info("Mitteilung „\(kind.title, privacy: .public)“ unterdrückt: ausgeschaltet.")
        case .quietHours:
            let range = "\(clock(settings.quietHoursStart))–\(clock(settings.quietHoursEnd))"
            logger.info("Mitteilung „\(kind.title, privacy: .public)“ unterdrückt: Ruhezeit \(range, privacy: .public).")
        case .weekend:
            logger.info("Mitteilung „\(kind.title, privacy: .public)“ unterdrückt: Wochenende still.")
        }
        return false
    }

    /// Wie `allows`, aber mit Begründung und ohne Log.
    @MainActor
    static func verdict(
        kind: NotificationKind,
        now: Date = .now,
        settings: some NotificationGateSettings,
        calendar: Calendar = .current
    ) -> Verdict {
        guard isEnabled(kind, settings: settings) else { return .disabled }
        guard !kind.ignoresQuietHours else { return .allowed }
        return quietVerdict(now: now, settings: settings, calendar: calendar)
    }

    /// Ruhezeit bzw. Wochenende zum Zeitpunkt `now`, unabhängig von der Art.
    @MainActor
    static func quietVerdict(
        now: Date = .now,
        settings: some NotificationGateSettings,
        calendar: Calendar = .current
    ) -> Verdict {
        if settings.notificationsWeekendQuiet, calendar.isDateInWeekend(now) { return .weekend }
        if settings.notificationsQuietHoursEnabled,
           isQuiet(minuteOfDay: minuteOfDay(now, calendar: calendar),
                   start: settings.quietHoursStart, end: settings.quietHoursEnd) {
            return .quietHours
        }
        return .allowed
    }

    /// Ob die Minute (seit Mitternacht) in der Ruhezeit `start..<end` liegt. `end < start` reicht
    /// über Mitternacht (18:00–08:00); `start == end` ist eine leere Ruhezeit.
    nonisolated static func isQuiet(minuteOfDay minute: Int, start: Int, end: Int) -> Bool {
        if start == end { return false }
        if start < end { return minute >= start && minute < end }
        return minute >= start || minute < end
    }

    nonisolated static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// „18:00“ aus Minuten seit Mitternacht.
    nonisolated static func clock(_ minutes: Int) -> String {
        let value = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    @MainActor
    private static func isEnabled(_ kind: NotificationKind, settings: some NotificationGateSettings) -> Bool {
        switch kind {
        case .breakReminder: settings.breakReminderEnabled
        case .pomodoro: settings.pomodoroNotificationsEnabled
        case .idle: settings.idleDetectionEnabled
        case .forgottenTimer: settings.forgottenTimerEnabled
        case .budget: settings.budgetWarningsEnabled
        case .activity: settings.activityNotificationsEnabled
        case .plannedBlock: settings.calendarPlannedBlockNotificationEnabled
        case .test: true
        }
    }
}
