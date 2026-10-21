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
                SettingsPage {
                    GeneralSettingsSection()
                    TimerSettingsSection()
                }
            }
            Tab("Mitteilungen", systemImage: "bell.badge", value: SettingsTab.notifications) {
                SettingsPage { NotificationsSettingsSection() }
            }
            Tab("Musik", systemImage: "music.note", value: SettingsTab.music) {
                SettingsPage { MusicSettingsSection() }
            }
            Tab("Fokus", systemImage: "cup.and.saucer", value: SettingsTab.focus) {
                SettingsPage { FocusSettingsSection() }
            }
            Tab("Widget", systemImage: "square.text.square", value: SettingsTab.widget) {
                SettingsPage { WidgetSettingsSection() }
            }
            Tab("Abrechnung", systemImage: "eurosign.circle", value: SettingsTab.billing) {
                SettingsPage { BillingSettingsSection() }
            }
            Tab("Kalender", systemImage: "calendar", value: SettingsTab.calendar) {
                SettingsPage { CalendarSettingsSection() }
            }
            Tab("Aktivität", systemImage: "sparkles", value: SettingsTab.activity) {
                SettingsPage { ActivitySettingsSection() }
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

/// Eine Seite im Einstellungsfenster: gruppiertes Formular.
private struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Form { content() }
            .formStyle(.grouped)
    }
}
