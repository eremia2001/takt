import SwiftUI
import TaktCore

/// Abschnitt „Timer“: Nachfrage bei vergessenem Timer (Schalter und Grenze).
struct TimerSettingsSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Section("Timer") {
            Toggle(isOn: $settings.forgottenTimerEnabled) {
                Text("Bei vergessenem Timer nachfragen")
                Text("Kommt auch in Ruhezeiten (Einstellungen › Mitteilungen).")
            }
            Stepper(value: $settings.forgottenTimerHours, in: 1...24) {
                Text(settings.forgottenTimerHours == 1
                     ? "Nach 1 Stunde nachfragen"
                     : "Nach \(settings.forgottenTimerHours) Stunden nachfragen")
            }
            .disabled(!settings.forgottenTimerEnabled)
        }
    }
}
