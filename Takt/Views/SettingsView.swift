import SwiftUI
import TaktCore

/// Einstellungsfenster: Reiter, die die Abschnitte aus `Takt/Settings/Sections/` einbinden.
/// Inhalt und Verhalten liegen in den Abschnitten; hier nur die Aufteilung.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Allgemein", systemImage: "gearshape") {
                SettingsPage {
                    GeneralSettingsSection()
                    TimerSettingsSection()
                }
            }
            Tab("Musik", systemImage: "music.note") {
                SettingsPage { MusicSettingsSection() }
            }
            Tab("Fokus", systemImage: "cup.and.saucer") {
                SettingsPage { FocusSettingsSection() }
            }
            Tab("Widget", systemImage: "square.text.square") {
                SettingsPage { WidgetSettingsSection() }
            }
            Tab("Abrechnung", systemImage: "eurosign.circle") {
                SettingsPage { BillingSettingsSection() }
            }
            Tab("Kalender", systemImage: "calendar") {
                SettingsPage { CalendarSettingsSection() }
            }
            Tab("Aktivität", systemImage: "sparkles") {
                SettingsPage { ActivitySettingsSection() }
            }
        }
        // 560 statt 500: Platz für sieben Reiter.
        .frame(width: 560, height: 420)
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
