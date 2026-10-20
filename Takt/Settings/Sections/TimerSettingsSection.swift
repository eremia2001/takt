import SwiftUI
import TaktCore

/// Abschnitt „Timer“: Grenze für die Nachfrage bei vergessenem Timer.
struct TimerSettingsSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Section("Timer") {
            Stepper(value: $settings.forgottenTimerHours, in: 1...24) {
                Text(settings.forgottenTimerHours == 1
                     ? "Nach 1 Stunde nachfragen"
                     : "Nach \(settings.forgottenTimerHours) Stunden nachfragen")
            }
        }
    }
}
