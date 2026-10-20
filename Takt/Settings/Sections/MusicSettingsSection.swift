import SwiftUI
import TaktCore

/// Abschnitt „Musik“: Anbieter, Standard-Quelle, Verhalten beim Stoppen.
struct MusicSettingsSection: View {
    @Environment(AppSettings.self) private var settings

    /// Eingabe im Feld „Standard-Quelle“; gespeichert wird nur eine erkannte Quelle
    /// (als `storageString`) oder nichts bei leerem Feld.
    @State private var sourceText = ""
    /// Ob Takt Tastenereignisse senden darf (für die Medientaste im Browser).
    @State private var mediaKeyAllowed = MediaKey.isAllowed()

    private var sourceResult: MusicLink.Result {
        MusicLink.parse(sourceText, preferring: settings.musicProvider)
    }

    var body: some View {
        @Bindable var settings = settings

        Section("Musik") {
            Toggle("Musik automatisch steuern", isOn: $settings.musicEnabled)

            Group {
                Picker("Bevorzugter Anbieter", selection: $settings.musicProvider) {
                    ForEach(MusicProvider.allCases, id: \.self) { provider in
                        Text(provider.title).tag(provider)
                    }
                }

                if settings.musicProvider == .none {
                    Text("Bei „Keine“ steuert Takt keine Musik, auch nicht für Projekte mit eigener Quelle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Group {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Standard-Quelle", text: $sourceText,
                                  prompt: Text("Link oder Playlist-Name, optional"))
                        sourceHint
                    }
                    Toggle("Beim Stoppen pausieren", isOn: $settings.pauseOnStop)
                    Toggle("Laufende Musik übernehmen", isOn: $settings.takeOverPlayingMusic)
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Browser: beim Stoppen Medientaste senden", isOn: $settings.browserPauseWithMediaKey)
                        browserHint
                    }
                }
                .disabled(settings.musicProvider == .none)

                Text(permissionNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!settings.musicEnabled)
        }
        .onAppear {
            sourceText = settings.defaultPlaylistURI ?? ""
            mediaKeyAllowed = MediaKey.isAllowed()
        }
        .onChange(of: sourceText) { storeSource() }
        .onChange(of: settings.musicProvider) { storeSource() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Nach Rückkehr aus den Systemeinstellungen neu prüfen.
            mediaKeyAllowed = MediaKey.isAllowed()
        }
    }

    // MARK: Teile

    @ViewBuilder
    private var sourceHint: some View {
        switch sourceResult {
        case .empty:
            Text("Für Projekte ohne eigene Quelle. Spotify-, Apple-Music-, YouTube- oder andere Links; Apple-Music-Playlists als „Apple Music: Name“.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .valid(let source):
            Label(MusicLink.summary(of: source), systemImage: source.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .invalid:
            Label("nicht erkannt", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(MusicLink.invalidHint)
        }
    }

    @ViewBuilder
    private var browserHint: some View {
        if settings.browserPauseWithMediaKey {
            if mediaKeyAllowed {
                Text("Die Medientaste wirkt auf das, was unter „Aktuell läuft“ steht, und schaltet um – war schon pausiert, spielt es wieder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("Für die Medientaste braucht Takt die Berechtigung „Bedienungshilfen“.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Freigeben …") {
                        mediaKeyAllowed = MediaKey.isAllowed(prompt: true)
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var permissionNote: String {
        "Beim ersten Abspielen fragt macOS, ob Takt „Spotify“ bzw. „Musik“ steuern darf (Automation). "
            + "Abgelehnt? Systemeinstellungen › Datenschutz & Sicherheit › Automation › Takt. "
            + "Apple-Music-Links öffnet Takt nur – abspielen lassen sich per Skript nur Playlists der eigenen Mediathek."
    }

    // MARK: Speichern

    /// Gleiche Erkennung wie im Projekt-Editor; nicht Erkanntes wird nicht übernommen.
    private func storeSource() {
        switch sourceResult {
        case .empty: settings.defaultPlaylistURI = nil
        case .valid(let source): settings.defaultPlaylistURI = source.storageString
        case .invalid: break
        }
    }
}
