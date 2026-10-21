import Foundation
import Observation
import os
import TaktCore
import UserNotifications

/// Budget-Warnungen: Mitteilung, wenn ein Projekt 80 % bzw. 100 % seines Stundenbudgets erreicht.
///
/// - Geprüft wird nach jeder Änderung im Store (Timer-Wechsel, neue/geänderte Einträge, geändertes
///   Budget – beobachtet über `running`, `budgetCompleted` und `projects`) und minütlich, solange
///   ein Timer läuft. Grundlage ist `store.budgetUsages()` (alle aktiven Projekte mit Budget).
/// - Jede Schwelle meldet sich **einmal** je Projekt. Merker in `UserDefaults` unter
///   `budgetWarned.<projectId>.<80|100>`; fällt der Anteil wieder unter die Schwelle (z. B. nach
///   einer Budgeterhöhung oder gelöschten Einträgen), wird der Merker gelöscht.
/// - Werden beide Schwellen auf einmal erreicht, kommt nur „Budget überschritten“.
/// - Nur mit `settings.budgetWarningsEnabled`; ausgeschaltet wird nichts geprüft und nichts gemerkt.
/// - Antwort („Projekt öffnen“ oder Klick) über `BreakReminder.addResponseHandler`
///   mit `handleNotificationResponse(_:)`: holt Takt mit „Heute“ nach vorn.
@MainActor
@Observable
final class BudgetWatcher {
    /// Schwellen in Prozent, aufsteigend.
    static let thresholds = [80, 100]

    @ObservationIgnored private let store: TaktStore
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var minuteTask: Task<Void, Never>?

    private static let logger = Logger(subsystem: "dev.eremiya.takt", category: "focus")

    init(store: TaktStore, settings: AppSettings, defaults: UserDefaults = .standard) {
        self.store = store
        self.settings = settings
        self.defaults = defaults

        observeContinuously { [weak self] in
            guard let self else { return }
            // Nur lesen (und damit beobachten); ausgewertet wird außerhalb der Beobachtung.
            let isRunning = self.store.running != nil
            _ = self.store.budgetCompleted
            _ = self.store.projects
            let enabled = self.settings.budgetWarningsEnabled
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.update(isRunning: isRunning, enabled: enabled) }
            }
        }
    }

    // MARK: Ablauf

    private func update(isRunning: Bool, enabled: Bool) {
        check()
        if isRunning && enabled {
            startMinuteLoop()
        } else {
            minuteTask?.cancel()
            minuteTask = nil
        }
    }

    /// Prüft minütlich, solange ein Timer läuft (der Verbrauch wächst mit).
    private func startMinuteLoop() {
        guard minuteTask == nil else { return }
        minuteTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self else { return }
                self.check()
            }
        }
    }

    /// Vergleicht den Verbrauch aller Projekte mit den Schwellen und meldet neu erreichte.
    func check(now: Date = .now) {
        guard settings.budgetWarningsEnabled else { return }
        for usage in store.budgetUsages(now: now) {
            var reached: Int?
            for threshold in Self.thresholds {
                let key = Self.key(projectId: usage.project.id, threshold: threshold)
                if usage.fraction >= Double(threshold) / 100 {
                    if !defaults.bool(forKey: key) {
                        defaults.set(true, forKey: key)
                        reached = threshold
                    }
                } else if defaults.object(forKey: key) != nil {
                    // Wieder darunter (Budget erhöht, Einträge gelöscht): Schwelle neu scharf.
                    defaults.removeObject(forKey: key)
                    Self.logger.info("Budget-Merker \(threshold) % zurückgesetzt (\(usage.project.name, privacy: .private)).")
                }
            }
            // Die höchste neu erreichte Schwelle zählt (80 und 100 auf einmal → nur „überschritten“).
            if let reached { notify(usage, threshold: reached) }
        }
    }

    // MARK: Mitteilung

    private func notify(_ usage: BudgetUsage, threshold: Int) {
        let content = UNMutableNotificationContent()
        let used = DurationFormat.hourMinute(usage.used)
        let budget = Self.hours(usage.budget)
        if threshold >= 100 {
            content.title = "Budget überschritten: \(usage.project.name)"
            content.body = "\(used) von \(budget) h"
        } else {
            content.title = "Budget \(threshold) %: \(usage.project.name)"
            content.body = "\(used) von \(budget) h verbraucht"
        }
        content.sound = .default
        content.categoryIdentifier = NotificationCategories.Budget.category
        content.userInfo = [Self.projectKey: usage.project.id.uuidString]
        // Eine Mitteilung je Projekt: „überschritten“ ersetzt die 80-%-Mitteilung.
        NotificationCategories.deliverNow(
            identifier: Self.requestPrefix + usage.project.id.uuidString, content: content,
            kind: .budget, settings: settings
        )
        Self.logger.info("Budget-Warnung \(threshold) %: \(usage.project.name, privacy: .private) (\(used, privacy: .public) von \(budget, privacy: .public) h).")
    }

    /// Antwort auf eine Budget-Mitteilung („Projekt öffnen“ oder Klick): Takt mit „Heute“ nach vorn.
    /// Für `BreakReminder.addResponseHandler`; `true`, wenn die Mitteilung eine Budget-Warnung war.
    nonisolated static func handleNotificationResponse(_ response: UNNotificationResponse) -> Bool {
        guard response.notification.request.content.categoryIdentifier == NotificationCategories.Budget.category else {
            return false
        }
        if response.actionIdentifier == NotificationCategories.Budget.open
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            Task { @MainActor in MenuBarController.showToday() }
        }
        return true
    }

    // MARK: Hilfen

    private static let requestPrefix = "dev.eremiya.takt.budget."
    private static let projectKey = "projectId"

    /// Merker-Schlüssel: `budgetWarned.<projectId>.<80|100>`.
    static func key(projectId: UUID, threshold: Int) -> String {
        "budgetWarned.\(projectId.uuidString).\(threshold)"
    }

    /// Budget in Stunden wie im Widget: „40“, „12,5“.
    static func hours(_ budget: TimeInterval) -> String {
        (budget / 3600).formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "de_DE")))
    }
}
