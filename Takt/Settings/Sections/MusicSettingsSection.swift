import SwiftUI
import TaktCore

/// Abschnitt „Musik“: automatische Steuerung, Standard-Playlist, Verhalten beim Stoppen.
struct MusicSettingsSection: View {
    @Environment(AppSettings.self) private var settings

    /// Eingabe im Playlist-Feld; gespeichert wird nur eine gültige URI (oder nichts bei leerem Feld).
    @State private var playlistText = ""

    private var playlistResult: SpotifyLink.Result { SpotifyLink.parse(playlistText) }

    var body: some View {
        @Bindable var settings = settings

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
    }
}
