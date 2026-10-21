import AppKit
import SwiftUI

/// Reiter „Mitteilungen“: alle Mitteilungsarten auf einen Blick.
///
/// - Oben der Systemstatus (erlaubt / verweigert / nicht entschieden) und „Testmitteilung senden“.
/// - Je Mitteilungsart eine Zeile mit Schalter, aktuellem Parameter und „Details →“ in den
///   zuständigen Reiter (über `AppNavigator`, optional in der Umgebung).
/// - Ruhezeiten und „Am Wochenende still“; ausgewertet von `NotificationGate`.
///
/// Systemzugriffe liegen in `NotificationPermission`, damit sich der Reiter ohne App rendern lässt.
struct NotificationsSettingsSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppNavigator.self) private var navigator: AppNavigator?
    @Environment(BreakReminder.self) private var breakReminder: BreakReminder?

    @State private var status: NotificationPermissionStatus?
    @State private var testResult: NotificationTestResult?
    @State private var isSendingTest = false

    var body: some View {
        @Bindable var settings = settings

        systemSection

        Section {
            KindRow(
                symbol: "cup.and.saucer.fill", color: .orange,
                title: "Pausenerinnerung",
                summary: "„Kurze Pause?“ nach langer Arbeit am Stück.",
                parameter: settings.pomodoroEnabled
                    ? "ruht bei Pomodoro"
                    : "nach \(settings.breakReminderMinutes) Min",
                isOn: $settings.breakReminderEnabled,
                details: detailsAction(.focus)
            )
            KindRow(
                symbol: "timer", color: .red,
                title: "Pomodoro",
                summary: "Pause beginnt, Pause vorbei. Die Einblendung bleibt immer.",
                parameter: settings.pomodoroEnabled
                    ? "\(settings.pomodoroWorkMinutes) / \(settings.pomodoroBreakMinutes) Min"
                    : "Modus aus",
                isOn: $settings.pomodoroNotificationsEnabled,
                details: detailsAction(.focus)
            )
            SubToggleRow(title: "Mit Ton", isOn: $settings.pomodoroSoundEnabled)
                .disabled(!settings.pomodoroNotificationsEnabled)
            KindRow(
                symbol: "moon.zzz.fill", color: .indigo,
                title: "Leerlauf",
                summary: "Fragt nach der Rückkehr, was mit der Zeit passieren soll.",
                parameter: "ab \(settings.idleMinutes) Min",
                isOn: $settings.idleDetectionEnabled,
                details: detailsAction(.focus)
            )
            KindRow(
                symbol: "clock.badge.exclamationmark.fill", color: .pink,
                title: "Vergessener Timer",
                summary: "Fragt nach, wenn ein Timer ungewöhnlich lange läuft.",
                parameter: "nach \(settings.forgottenTimerHours) h",
                isOn: $settings.forgottenTimerEnabled,
                details: detailsAction(.general)
            )
            KindRow(
                symbol: "gauge.with.dots.needle.67percent", color: .green,
                title: "Budget",
                summary: "Hinweis, wenn ein Projekt sein Stundenbudget fast oder ganz verbraucht.",
                parameter: "80 % · 100 %",
                isOn: $settings.budgetWarningsEnabled,
                details: nil
            )
            KindRow(
                symbol: "sparkles", color: .purple,
                title: "Aktivität",
                summary: "Vorschlag, wenn der Timer nicht zur Arbeit passt. Aus: nur ohne Mitteilung.",
                parameter: settings.activitySuggestionsEnabled
                    ? "nach \(settings.activityMismatchMinutes) Min"
                    : "Erkennung aus",
                isOn: $settings.activityNotificationsEnabled,
                details: detailsAction(.activity)
            )
            KindRow(
                symbol: "calendar.badge.clock", color: .blue,
                title: "Geplanter Block",
                summary: "„Geplant: … um 14:00“ zum Beginn, wenn kein Timer läuft.",
                parameter: "zum Beginn",
                isOn: $settings.calendarPlannedBlockNotificationEnabled,
                details: nil
            )
            KindRow(
                symbol: "calendar", color: .teal,
                title: "Termin-Hinweis",
                badge: "in der App",
                summary: "Zeile in „Heute“, wenn ein Termin läuft und der Timer woanders steht.",
                parameter: settings.calendarShowEvents ? "in „Heute“" : "Termine aus",
                isOn: $settings.calendarMeetingHintEnabled,
                details: detailsAction(.calendar)
            )
        } header: {
            Text("Mitteilungsarten")
        }
        .onChange(of: settings.breakReminderEnabled) { breakReminder?.settingsDidChange() }
        .onChange(of: settings.calendarPlannedBlockNotificationEnabled) { breakReminder?.settingsDidChange() }

        quietHoursSection
    }

    // MARK: Systemstatus

    @ViewBuilder
    private var systemSection: some View {
        Section {
            LabeledContent {
                switch status {
                case .notDetermined:
                    Button("Erlauben") {
                        Task { status = await NotificationPermission.request() }
                    }
                    .buttonStyle(.borderedProminent)
                case .denied:
                    Button("In Systemeinstellungen öffnen") { NotificationPermission.openSystemSettings() }
                        .buttonStyle(.borderedProminent)
                case .allowed:
                    Button("In Systemeinstellungen öffnen") { NotificationPermission.openSystemSettings() }
                case nil:
                    ProgressView().controlSize(.small)
                }
            } label: {
                Label {
                    Text(statusTitle)
                    Text(statusDetail)
                } icon: {
                    Image(systemName: statusSymbol)
                        .foregroundStyle(statusColor)
                }
            }

            LabeledContent {
                Button("Testmitteilung senden") { sendTest() }
                    .disabled(isSendingTest || status == .denied)
            } label: {
                Text("Kommt alles an?")
                Text(testDetail)
            }
        } header: {
            Text("System")
        }
        .task { status = await NotificationPermission.status() }
        // Zurück aus den Systemeinstellungen: Status neu lesen.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { status = await NotificationPermission.status() }
        }
    }

    private var statusTitle: String {
        switch status {
        case .allowed(let showsAlerts): showsAlerts ? "Mitteilungen erlaubt" : "Erlaubt, aber ohne Banner"
        case .denied: "Mitteilungen verweigert"
        case .notDetermined: "Noch nicht entschieden"
        case nil: "Mitteilungen"
        }
    }

    private var statusDetail: String {
        switch status {
        case .allowed(let showsAlerts):
            showsAlerts
                ? "Takt darf Banner zeigen. Ton und Stil regelt macOS."
                : "Hinweisstil „Keine“: Mitteilungen landen nur in der Mitteilungszentrale."
        case .denied:
            "Erlaube sie in den Systemeinstellungen unter Mitteilungen › Takt."
        case .notDetermined:
            "macOS fragt einmal nach. Ohne Erlaubnis kommen keine Erinnerungen und Nachfragen."
        case nil:
            "Status wird gelesen …"
        }
    }

    private var statusSymbol: String {
        switch status {
        case .allowed(let showsAlerts): showsAlerts ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        case .denied: "xmark.octagon.fill"
        case .notDetermined, nil: "questionmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .allowed(let showsAlerts): showsAlerts ? .green : .orange
        case .denied: .red
        case .notDetermined, nil: .orange
        }
    }

    private var testDetail: String {
        switch testResult {
        case .sent(let date):
            "Gesendet um \(date.formatted(date: .omitted, time: .shortened)). Nichts gesehen? Fokus-Modus und Systemeinstellungen prüfen."
        case .notAllowed:
            "Nicht gesendet: Mitteilungen sind nicht erlaubt."
        case .failed(let message):
            "Nicht gesendet: \(message)"
        case nil:
            "Schickt sofort eine Mitteilung – auch in Ruhezeiten."
        }
    }

    private func sendTest() {
        isSendingTest = true
        Task {
            testResult = await NotificationPermission.sendTest(settings: settings)
            status = await NotificationPermission.status()
            isSendingTest = false
        }
    }

    // MARK: Ruhezeiten

    @ViewBuilder
    private var quietHoursSection: some View {
        @Bindable var settings = settings

        Section {
            Toggle(isOn: $settings.notificationsQuietHoursEnabled) {
                Text("Ruhezeiten")
                Text("In diesem Zeitraum kommen keine Mitteilungen.")
            }
            LabeledContent("Zeitraum") {
                HStack(spacing: 8) {
                    DatePicker("Von", selection: timeBinding(\.quietHoursStart), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text("bis")
                        .foregroundStyle(.secondary)
                    DatePicker("Bis", selection: timeBinding(\.quietHoursEnd), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }
            .disabled(!settings.notificationsQuietHoursEnabled)
            Toggle(isOn: $settings.notificationsWeekendQuiet) {
                Text("Am Wochenende still")
                Text("Samstag und Sonntag ganztägig.")
            }
        } header: {
            Text("Ruhezeiten")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    if let text = quietNowText(at: context.date) {
                        Label(text, systemImage: "moon.fill")
                    }
                }
                Label("Vergessener Timer bleibt aktiv – er kommt auch in Ruhezeiten.", systemImage: "info.circle")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .onChange(of: settings.notificationsQuietHoursEnabled) { breakReminder?.settingsDidChange() }
        .onChange(of: settings.quietHoursStart) { breakReminder?.settingsDidChange() }
        .onChange(of: settings.quietHoursEnd) { breakReminder?.settingsDidChange() }
        .onChange(of: settings.notificationsWeekendQuiet) { breakReminder?.settingsDidChange() }
    }

    /// „Gerade Ruhezeit – bis 08:00“ bzw. „Wochenende – Mitteilungen ruhen“, sonst `nil`.
    private func quietNowText(at date: Date) -> String? {
        switch NotificationGate.quietVerdict(now: date, settings: settings) {
        case .quietHours: "Gerade Ruhezeit – Mitteilungen ruhen bis \(NotificationGate.clock(settings.quietHoursEnd))."
        case .weekend: "Wochenende – Mitteilungen ruhen."
        case .allowed, .disabled: nil
        }
    }

    /// Minuten seit Mitternacht ↔ Uhrzeit von heute (für `DatePicker`).
    private func timeBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, Int>) -> Binding<Date> {
        let settings = settings
        return Binding {
            let minutes = settings[keyPath: keyPath]
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        } set: { date in
            settings[keyPath: keyPath] = NotificationGate.minuteOfDay(date)
        }
    }

    private func detailsAction(_ tab: SettingsTab) -> (() -> Void)? {
        guard let navigator else { return nil }
        return { navigator.request(settingsTab: tab.rawValue) }
    }
}

// MARK: - Zeilen

/// Eine Mitteilungsart: Symbol, Titel mit dezentem Parameter, Kurzbeschreibung, „Details →“, Schalter.
private struct KindRow: View {
    let symbol: String
    let color: Color
    let title: String
    var badge: String?
    let summary: String
    let parameter: String
    @Binding var isOn: Bool
    let details: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .opacity(isOn ? 1 : 0.45)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                    Text(parameter)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let details {
                Button("Details →", action: details)
                    .buttonStyle(.link)
                    .font(.callout)
                    .help("Einstellungen zu „\(title)“")
            }

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Eingerückter Unterschalter (z. B. „Mit Ton“ unter Pomodoro).
private struct SubToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 34)
    }
}
