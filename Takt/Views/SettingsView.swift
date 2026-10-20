import SwiftUI
import TaktCore
import WidgetKit

/// Einstellungen: Musik, Pausenerinnerung, vergessener Timer, Widget-Stil.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BreakReminder.self) private var breakReminder

    /// Eingabe im Playlist-Feld; gespeichert wird nur eine gültige URI (oder nichts bei leerem Feld).
    @State private var playlistText = ""

    private var playlistResult: SpotifyLink.Result { SpotifyLink.parse(playlistText) }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Musik") {
                Toggle("Musik automatisch steuern", isOn: $settings.musicEnabled)

                Group {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Standard-Playlist (Spotify-Link)", text: $playlistText, prompt: Text("Link, optional"))
                        if playlistResult == .invalid {
                            Text("Kein gültiger Spotify-Link (Playlist, Album oder Titel).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Beim Stoppen pausieren", isOn: $settings.pauseOnStop)
                    Toggle("Laufende Musik übernehmen", isOn: $settings.takeOverPlayingMusic)
                }
                .disabled(!settings.musicEnabled)
            }

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

            Section("Timer") {
                Stepper(value: $settings.forgottenTimerHours, in: 1...24) {
                    Text(settings.forgottenTimerHours == 1
                         ? "Nach 1 Stunde nachfragen"
                         : "Nach \(settings.forgottenTimerHours) Stunden nachfragen")
                }
            }

            Section("Widget") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Stil", selection: $settings.widgetStyle) {
                        ForEach(WidgetStyle.allCases, id: \.self) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(settings.widgetStyle.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 520)
        .onAppear {
            playlistText = settings.defaultPlaylistURI ?? ""
        }
        .onChange(of: playlistText) {
            // Gleiche Umwandlung wie im Projekt-Editor; Ungültiges wird nicht übernommen.
            switch playlistResult {
            case .empty: settings.defaultPlaylistURI = nil
            case .valid(let uri): settings.defaultPlaylistURI = uri
            case .invalid: break
            }
        }
        .onChange(of: settings.breakReminderEnabled) { breakReminder.settingsDidChange() }
        .onChange(of: settings.breakReminderMinutes) { breakReminder.settingsDidChange() }
        // Widget sofort im neuen Stil zeichnen statt erst bei der nächsten Timeline.
        .onChange(of: settings.widgetStyle) { WidgetCenter.shared.reloadAllTimelines() }
    }
}
