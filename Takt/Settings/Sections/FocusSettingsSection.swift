import SwiftUI
import TaktCore

/// Reiter „Fokus“: Pausenerinnerung, Leerlauf-Erkennung und Pomodoro.
/// Das Ein- und Ausschalten von Pomodoro meldet der `PomodoroController` selbst an die
/// Pausenerinnerung (die bei aktivem Pomodoro ruht).
struct FocusSettingsSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BreakReminder.self) private var breakReminder

    var body: some View {
        @Bindable var settings = settings

        Section {
            Toggle("An Pausen erinnern", isOn: $settings.breakReminderEnabled)
            Group {
                Stepper(value: $settings.breakReminderMinutes, in: 15...180, step: 5) {
                    Text("Nach \(settings.breakReminderMinutes) Minuten")
                }
                Toggle("Musik dabei pausieren", isOn: $settings.breakPausesMusic)
                    .disabled(!settings.musicEnabled)
            }
            .disabled(!settings.breakReminderEnabled)
        } header: {
            Text("Pausen")
        } footer: {
            if settings.pomodoroEnabled && settings.breakReminderEnabled {
                Text("Ruht, solange der Pomodoro-Modus eingeschaltet ist.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: settings.breakReminderEnabled) { breakReminder.settingsDidChange() }
        .onChange(of: settings.breakReminderMinutes) { breakReminder.settingsDidChange() }

        Section("Leerlauf") {
            Toggle(isOn: $settings.idleDetectionEnabled) {
                Text("Leerlauf erkennen")
                Text("Läuft ein Timer, während du nicht am Mac bist (keine Eingaben, Ruhezustand oder Sperre), fragt Takt bei deiner Rückkehr, was mit der Zeit passieren soll.")
            }
            Stepper(value: $settings.idleMinutes, in: 1...120) {
                Text(settings.idleMinutes == 1
                     ? "Nach 1 Minute ohne Eingabe"
                     : "Nach \(settings.idleMinutes) Minuten ohne Eingabe")
            }
            .disabled(!settings.idleDetectionEnabled)
        }

        Section("Pomodoro") {
            Toggle(isOn: $settings.pomodoroEnabled) {
                Text("Pomodoro-Modus")
                Text("Arbeit und Pausen im Wechsel, beginnend mit dem Timer-Start. Ersetzt die Pausenerinnerung.")
            }
            Group {
                Stepper(value: $settings.pomodoroWorkMinutes, in: 5...180, step: 5) {
                    Text("Arbeit: \(settings.pomodoroWorkMinutes) Minuten")
                }
                Stepper(value: $settings.pomodoroBreakMinutes, in: 1...60) {
                    Text(settings.pomodoroBreakMinutes == 1 ? "Pause: 1 Minute" : "Pause: \(settings.pomodoroBreakMinutes) Minuten")
                }
                Stepper(value: $settings.pomodoroLongBreakMinutes, in: 1...120) {
                    Text(settings.pomodoroLongBreakMinutes == 1 ? "Lange Pause: 1 Minute" : "Lange Pause: \(settings.pomodoroLongBreakMinutes) Minuten")
                }
                Stepper(value: $settings.pomodoroCyclesBeforeLongBreak, in: 1...12) {
                    Text(settings.pomodoroCyclesBeforeLongBreak == 1
                         ? "Lange Pause nach jeder Einheit"
                         : "Lange Pause nach \(settings.pomodoroCyclesBeforeLongBreak) Einheiten")
                }
                Toggle(isOn: $settings.pomodoroAutoStopTimer) {
                    Text("Timer in der Pause automatisch stoppen")
                    Text("Pausen werden nicht erfasst; die Musik pausiert mit.")
                }
            }
            .disabled(!settings.pomodoroEnabled)
        }
    }
}
