import SwiftUI
import TaktCore

/// Reiter „Fokus“: Pausenerinnerung, Leerlauf-Erkennung und Pomodoro.
/// Das Ein- und Ausschalten von Pomodoro meldet der `PomodoroController` selbst an die
/// Pausenerinnerung (die bei aktivem Pomodoro ruht).
/// Oben die Freigabe „Mitteilungen“, weil Erinnerung, Leerlauf-Nachfrage und Pomodoro sie brauchen.
struct FocusSettingsSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BreakReminder.self) private var breakReminder

    var body: some View {
        @Bindable var settings = settings

        Section {
            NotificationPermissionRow(
                purpose: "Für Pausenerinnerung, Pomodoro-Wechsel und die Nachfrage nach einem Leerlauf, wenn Takt im Hintergrund ist."
            )
        } header: {
            Text("Freigabe")
        }

        Section {
            Toggle(isOn: $settings.breakReminderEnabled) {
                Text("An Pausen erinnern")
                Text("Nach langer Arbeit am Stück schlägt Takt per Mitteilung eine kurze Pause vor. Der Timer läuft dabei weiter.")
            }
            Group {
                Stepper(value: $settings.breakReminderMinutes, in: 15...180, step: 5) {
                    Text("Erinnern nach \(settings.breakReminderMinutes) Min am Stück")
                        .monospacedDigit()
                    Text("Standard: 75 Min · in 5-Minuten-Schritten")
                }
                Toggle(isOn: $settings.breakPausesMusic) {
                    Text("Musik dabei pausieren")
                    Text(settings.musicEnabled
                         ? "Hält die Musik an, sobald die Erinnerung kommt."
                         : "Erst möglich, wenn Musik unter Einstellungen › Musik eingeschaltet ist.")
                }
                .disabled(!settings.musicEnabled)
            }
            .disabled(!settings.breakReminderEnabled)
        } header: {
            Text("Pausen")
        } footer: {
            if settings.pomodoroEnabled && settings.breakReminderEnabled {
                Text("Ruht, solange der Pomodoro-Modus eingeschaltet ist – dann gibt Pomodoro die Pausen vor.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: settings.breakReminderEnabled) { breakReminder.settingsDidChange() }
        .onChange(of: settings.breakReminderMinutes) { breakReminder.settingsDidChange() }

        Section {
            Toggle(isOn: $settings.idleDetectionEnabled) {
                Text("Leerlauf erkennen")
                Text("Läuft ein Timer, während du nicht am Mac bist (keine Eingaben, Ruhezustand oder Sperre), fragt Takt bei deiner Rückkehr: abziehen, behalten oder bei Beginn des Leerlaufs stoppen.")
            }
            Stepper(value: $settings.idleMinutes, in: 1...120) {
                Text("Leerlauf ab \(settings.idleMinutes) Min ohne Eingabe")
                    .monospacedDigit()
                Text("Standard: 10 Min · kürzer fragt öfter, z. B. schon beim Lesen")
            }
            .disabled(!settings.idleDetectionEnabled)
        } header: {
            Text("Leerlauf")
        }

        Section {
            Toggle(isOn: $settings.pomodoroEnabled) {
                Text("Pomodoro-Modus")
                Text("Feste Arbeitseinheiten und Pausen im Wechsel, beginnend mit dem Timer-Start. Ersetzt die Pausenerinnerung.")
            }
            Group {
                Stepper(value: $settings.pomodoroWorkMinutes, in: 5...180, step: 5) {
                    Text("Arbeit: \(settings.pomodoroWorkMinutes) Min")
                        .monospacedDigit()
                    Text("Standard: 50 Min")
                }
                Stepper(value: $settings.pomodoroBreakMinutes, in: 1...60) {
                    Text("Kurze Pause: \(settings.pomodoroBreakMinutes) Min")
                        .monospacedDigit()
                    Text("Standard: 10 Min")
                }
                Stepper(value: $settings.pomodoroLongBreakMinutes, in: 1...120) {
                    Text("Lange Pause: \(settings.pomodoroLongBreakMinutes) Min")
                        .monospacedDigit()
                    Text("Standard: 20 Min")
                }
                Stepper(value: $settings.pomodoroCyclesBeforeLongBreak, in: 1...12) {
                    Text(settings.pomodoroCyclesBeforeLongBreak == 1
                         ? "Lange Pause nach jeder Einheit"
                         : "Lange Pause nach \(settings.pomodoroCyclesBeforeLongBreak) Einheiten")
                        .monospacedDigit()
                    Text("Standard: 4 Einheiten")
                }
                Toggle(isOn: $settings.pomodoroAutoStopTimer) {
                    Text("Timer in der Pause automatisch stoppen")
                    Text("Pausen werden dann nicht als Arbeitszeit erfasst; die Musik pausiert mit. Nach der Pause startest du neu.")
                }
            }
            .disabled(!settings.pomodoroEnabled)
        } header: {
            Text("Pomodoro")
        } footer: {
            Text("Mitteilungen und Ton für Pomodoro stellst du unter Einstellungen › Mitteilungen ein.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
