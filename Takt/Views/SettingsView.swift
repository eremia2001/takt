import SwiftUI
import TaktCore

/// Kennungen der Reiter im Einstellungsfenster. Der Rohwert ist die Kennung, die
/// `AppNavigator.request(settingsTab:)` erwartet (z. B. "notifications").
enum SettingsTab: String, CaseIterable, Hashable {
    case general, notifications, music, focus, widget, billing, calendar, activity
}

/// Einstellungsfenster: Reiter, die die Abschnitte aus `Takt/Settings/Sections/` einbinden.
/// Inhalt und Verhalten liegen in den Abschnitten; hier nur die Aufteilung und die Auswahl.
///
/// Der gewählte Reiter lässt sich über `AppNavigator.requestedSettingsTab` anfordern (Befehlspalette,
/// Menüleiste, Links „Details →“ im Reiter „Mitteilungen“); der Navigator ist optional in der Umgebung.
struct SettingsView: View {
    @Environment(AppNavigator.self) private var navigator: AppNavigator?
    @State private var selection: SettingsTab = .general

    var body: some View {
        TabView(selection: $selection) {
            Tab("Allgemein", systemImage: "gearshape", value: SettingsTab.general) {
                SettingsPage(
                    symbol: "gearshape",
                    intro: "Hier stellst du ein, wie Takt in der Menüleiste erscheint, welche Kurzbefehle überall gelten und wann Takt bei einem vergessenen Timer nachfragt.",
                    helpTopic: "menubar"
                ) {
                    GeneralSettingsSection()
                    TimerSettingsSection()
                }
            }
            Tab("Mitteilungen", systemImage: "bell.badge", value: SettingsTab.notifications) {
                SettingsPage(
                    symbol: "bell.badge",
                    intro: "Hier siehst du alle Hinweise, die Takt schicken kann, schaltest sie einzeln ein oder aus und legst Ruhezeiten fest.",
                    helpTopic: "notifications"
                ) { NotificationsSettingsSection() }
            }
            Tab("Musik", systemImage: "music.note", value: SettingsTab.music) {
                SettingsPage(
                    symbol: "music.note",
                    intro: "Hier stellst du ein, ob Takt beim Starten eines Timers Musik abspielt und beim Stoppen pausiert. Die Musik je Projekt legst du im Projekt fest.",
                    helpTopic: "music"
                ) { MusicSettingsSection() }
            }
            Tab("Fokus", systemImage: "brain.head.profile", value: SettingsTab.focus) {
                SettingsPage(
                    symbol: "brain.head.profile",
                    intro: "Hier stellst du ein, wann Takt an Pausen erinnert, was nach einer Abwesenheit mit der Zeit passiert und ob du im Pomodoro-Rhythmus arbeitest.",
                    helpTopic: "focus"
                ) { FocusSettingsSection() }
            }
            Tab("Widget", systemImage: "rectangle.3.group", value: SettingsTab.widget) {
                SettingsPage(
                    symbol: "rectangle.3.group",
                    intro: "Hier stellst du ein, wie das Takt-Widget auf dem Schreibtisch und in der Mitteilungszentrale aussieht.",
                    helpTopic: "widget"
                ) { WidgetSettingsSection() }
            }
            Tab("Abrechnung", systemImage: "eurosign.circle", value: SettingsTab.billing) {
                SettingsPage(
                    symbol: "eurosign.circle",
                    intro: "Hier stellst du Stundensatz, Wochenziel, Rundung und Währung ein. Sie wirken auf Berichte, Umsatz und Export – nicht auf die erfasste Zeit.",
                    helpTopic: "billing"
                ) { BillingSettingsSection() }
            }
            Tab("Kalender", systemImage: "calendar", value: SettingsTab.calendar) {
                SettingsPage(
                    symbol: "calendar",
                    intro: "Hier verbindest du Takt mit deinen Kalendern: Termine in „Heute“ zeigen, erfasste Zeiten in einen eigenen Kalender eintragen und Termine Projekten zuordnen.",
                    helpTopic: "calendar"
                ) { CalendarSettingsSection() }
            }
            Tab("Aktivität", systemImage: "sparkles", value: SettingsTab.activity) {
                SettingsPage(
                    symbol: "sparkles",
                    intro: "Hier stellst du ein, ob Takt erkennt, woran du gerade arbeitest, und sich meldet, wenn der Timer nicht dazu passt. Alles bleibt auf diesem Mac.",
                    helpTopic: "activity"
                ) { ActivitySettingsSection() }
            }
        }
        // 640 × 460: Platz für acht Reiter in der Symbolleiste und die Übersicht „Mitteilungen“.
        .frame(width: 640, height: 460)
        // Anforderung auch übernehmen, wenn sie schon vor dem Öffnen des Fensters gesetzt wurde.
        .onChange(of: navigator?.requestedSettingsTab, initial: true) {
            guard let raw = navigator?.consumeSettingsTab() else { return }
            if let tab = SettingsTab(rawValue: raw) { selection = tab }
        }
    }
}

/// Eine Seite im Einstellungsfenster: gruppiertes Formular, oben ein Einleitungssatz
/// („Hier stellst du ein, …“), unten der Link „Mehr in der Hilfe →“ zum passenden Thema.
struct SettingsPage<Content: View>: View {
    let symbol: String
    let intro: String
    /// Kennung des Hilfe-Themas (siehe `HelpOpener`).
    let helpTopic: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        Form {
            Section {
                SettingsIntro(symbol: symbol, text: intro)
            }
            content()
            Section {
            } footer: {
                HStack {
                    Spacer()
                    HelpLink(topic: helpTopic)
                }
            }
        }
        .formStyle(.grouped)
    }
}
