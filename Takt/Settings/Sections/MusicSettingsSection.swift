import AppKit
import CoreServices
import SwiftUI
import TaktCore

/// Abschnitt „Musik“: Anbieter, Standard-Quelle, Verhalten beim Stoppen und die nötigen Freigaben
/// (Automation für Spotify/Musik, Bedienungshilfen für die Medientaste) als `PermissionRow`.
struct MusicSettingsSection: View {
    @Environment(AppSettings.self) private var settings

    /// Eingabe im Feld „Standard-Quelle“; gespeichert wird nur eine erkannte Quelle
    /// (als `storageString`) oder nichts bei leerem Feld.
    @State private var sourceText = ""
    /// Ob Takt Tastenereignisse senden darf (für die Medientaste im Browser).
    @State private var mediaKeyAllowed = MediaKey.isAllowed()
    /// Automation-Status je Bundle-ID (Spotify, Musik).
    @State private var automationStates: [String: PermissionState] = [:]

    private var sourceResult: MusicLink.Result {
        MusicLink.parse(sourceText, preferring: settings.musicProvider)
    }

    var body: some View {
        @Bindable var settings = settings

        Section {
            Toggle(isOn: $settings.musicEnabled) {
                Text("Musik automatisch steuern")
                Text("Beim Start eines Timers spielt Takt die Musik des Projekts (sonst die Standard-Quelle), beim Stoppen pausiert sie.")
            }

            Group {
                Picker(selection: $settings.musicProvider) {
                    ForEach(MusicProvider.allCases, id: \.self) { provider in
                        Text(provider.title).tag(provider)
                    }
                } label: {
                    Text("Bevorzugter Anbieter")
                    Text(settings.musicProvider == .none
                         ? "Bei „Keine“ steuert Takt keine Musik, auch nicht für Projekte mit eigener Quelle."
                         : "Womit Playlist-Namen ohne Link abgespielt werden. Links (Spotify, Apple Music, YouTube …) wählen den Anbieter selbst.")
                }

                Group {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Standard-Quelle", text: $sourceText,
                                  prompt: Text("Link oder Playlist-Name, optional"))
                        sourceHint
                    }
                    Toggle(isOn: $settings.pauseOnStop) {
                        Text("Beim Stoppen pausieren")
                        Text("Stoppst du den Timer, hält auch die Musik an.")
                    }
                    Toggle(isOn: $settings.takeOverPlayingMusic) {
                        Text("Laufende Musik übernehmen")
                        Text("An: Spielt schon etwas anderes, ersetzt Takt es durch die Projektmusik. Aus: Laufende Musik bleibt unangetastet.")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: $settings.browserPauseWithMediaKey) {
                            Text("Browser: beim Stoppen Medientaste senden")
                            Text("Für Musik im Browser (z. B. YouTube Music), die sich nicht direkt steuern lässt.")
                        }
                        browserHint
                    }
                }
                .disabled(settings.musicProvider == .none)
            }
            .disabled(!settings.musicEnabled)
        } header: {
            Text("Musik")
        }

        Section {
            ForEach(automationTargets, id: \.bundleID) { target in
                PermissionRow(
                    symbol: "applescript",
                    title: "Automation: \(target.name)",
                    state: automationStates[target.bundleID] ?? .checking,
                    purpose: "Damit Takt \(target.name) starten und pausieren darf. macOS fragt beim ersten Abspielen.",
                    request: { requestAutomation(target.bundleID) },
                    openSettings: { Self.openSettings("Privacy_Automation") }
                )
            }
            if settings.browserPauseWithMediaKey {
                PermissionRow(
                    symbol: "accessibility",
                    title: "Bedienungshilfen",
                    state: mediaKeyAllowed ? .granted() : .notDetermined("Nicht erlaubt"),
                    purpose: "Nur für die Medientaste im Browser: Takt sendet dafür einen Tastendruck.",
                    request: { mediaKeyAllowed = MediaKey.isAllowed(prompt: true) },
                    openSettings: { Self.openSettings("Privacy_Accessibility") }
                )
            }
        } header: {
            Text("Freigaben")
        } footer: {
            Text("Apple-Music-Links öffnet Takt nur – abspielen lassen sich per Skript nur Playlists der eigenen Mediathek.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: settings.musicProvider) { await refreshAutomation() }
        .onAppear {
            sourceText = settings.defaultPlaylistURI ?? ""
            mediaKeyAllowed = MediaKey.isAllowed()
        }
        .onChange(of: sourceText) { storeSource() }
        .onChange(of: settings.musicProvider) { storeSource() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Nach Rückkehr aus den Systemeinstellungen neu prüfen.
            mediaKeyAllowed = MediaKey.isAllowed()
            Task { await refreshAutomation() }
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
        if settings.browserPauseWithMediaKey, mediaKeyAllowed {
            Text("Die Medientaste wirkt auf das, was unter „Aktuell läuft“ steht, und schaltet um – war schon pausiert, spielt es wieder.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Automation

    /// Apps, die Takt per Apple Events steuert: der bevorzugte Anbieter (Spotify/Musik); beim
    /// Browser oder „Keine“ keine.
    private var automationTargets: [(name: String, bundleID: String)] {
        guard settings.musicEnabled else { return [] }
        switch settings.musicProvider {
        case .spotify: return [("Spotify", "com.spotify.client")]
        case .appleMusic: return [("Musik", "com.apple.Music")]
        case .browser, .none: return []
        }
    }

    private func refreshAutomation() async {
        for target in automationTargets {
            let id = target.bundleID
            let state = await Task.detached { AutomationPermission.state(bundleID: id, ask: false) }.value
            automationStates[id] = state
        }
    }

    private func requestAutomation(_ bundleID: String) {
        automationStates[bundleID] = .checking
        Task {
            let state = await Task.detached { AutomationPermission.state(bundleID: bundleID, ask: true) }.value
            automationStates[bundleID] = state
        }
    }

    private static func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
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

// MARK: - Automation-Freigabe

/// Liest den Automation-Status (Apple Events) für eine App, ohne Musik-Logik zu berühren.
/// `ask: true` zeigt die Systemabfrage. Kann kurz blockieren – nicht auf dem Main-Thread aufrufen.
enum AutomationPermission {
    static func state(bundleID: String, ask: Bool) -> PermissionState {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            // Ohne laufende App kann macOS den Status nicht liefern.
            return .notDetermined("Prüfbar, wenn die App läuft")
        }
        var target = AEAddressDesc()
        let bytes = Array(bundleID.utf8)
        let created = bytes.withUnsafeBytes { buffer in
            AECreateDesc(DescType(typeApplicationBundleID), buffer.baseAddress, buffer.count, &target)
        }
        guard created == OSErr(noErr) else { return .notDetermined("Unbekannt") }
        defer { AEDisposeDesc(&target) }
        let status = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
        switch status {
        case OSStatus(noErr): return .granted()
        case OSStatus(errAEEventNotPermitted): return .denied()
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined("Noch nicht gefragt")
        default: return .notDetermined("Prüfbar, wenn die App läuft")
        }
    }
}
