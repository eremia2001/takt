import SwiftUI
import TaktCore

/// Abschnitt „Timer“: Nachfrage bei vergessenem Timer (Schalter und Grenze).
struct TimerSettingsSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Section {
            Toggle(isOn: $settings.forgottenTimerEnabled) {
                Text("Bei vergessenem Timer nachfragen")
                Text("Läuft ein Timer ungewöhnlich lange, fragt Takt, ob er wirklich noch läuft – mit „Jetzt stoppen“ oder „Stoppen um …“. Kommt auch in Ruhezeiten.")
            }
            Stepper(value: $settings.forgottenTimerHours, in: 1...24) {
                Text("Nachfragen nach \(settings.forgottenTimerHours) h")
                    .monospacedDigit()
                Text("Standard: 8 h · 1 bis 24 h")
            }
            .disabled(!settings.forgottenTimerEnabled)
        } header: {
            Text("Vergessener Timer")
        }
    }
}
