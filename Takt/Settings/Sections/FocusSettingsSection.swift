import SwiftUI
import TaktCore

/// Abschnitt „Pausen“: Pausenerinnerung und ob die Musik dabei pausiert.
struct FocusSettingsSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BreakReminder.self) private var breakReminder

    var body: some View {
        @Bindable var settings = settings

        Section("Pausen") {
            Toggle("An Pausen erinnern", isOn: $settings.breakReminderEnabled)
            Group {
                Stepper(value: $settings.breakReminderMinutes, in: 15...180, step: 5) {
                    Text("Nach \(settings.breakReminderMinutes) Minuten")
                }
                Toggle("Musik dabei pausieren", isOn: $settings.breakPausesMusic)
                    .disabled(!settings.musicEnabled)
            }
            .disabled(!settings.breakReminderEnabled)
        }
        .onChange(of: settings.breakReminderEnabled) { breakReminder.settingsDidChange() }
        .onChange(of: settings.breakReminderMinutes) { breakReminder.settingsDidChange() }
    }
}
