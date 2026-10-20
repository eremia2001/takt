import SwiftUI
import TaktCore

/// Neues (`project == nil`) oder zu bearbeitendes Projekt für das Sheet.
struct ProjectDraft: Identifiable {
    let id = UUID()
    let project: Project?
}

/// Sheet zum Anlegen und Bearbeiten eines Projekts.
struct ProjectEditor: View {
    @Environment(TaktStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let draft: ProjectDraft

    @State private var name: String
    @State private var colorHex: String
    @State private var isBusiness: Bool
    @State private var playlist: String
    @State private var errorMessage: String?

    /// Namen der Palettenfarben (gleiche Reihenfolge wie `ProjectPalette.colors`) für VoiceOver.
    private static let colorNames = ["Blau", "Teal", "Indigo", "Orange", "Pink", "Grün", "Grau", "Braun"]

    init(draft: ProjectDraft) {
        self.draft = draft
        _name = State(initialValue: draft.project?.name ?? "")
        _colorHex = State(initialValue: draft.project?.colorHex ?? "")
        _isBusiness = State(initialValue: draft.project?.isBusiness ?? true)
        _playlist = State(initialValue: draft.project?.playlistURI ?? "")
    }

    private var isNew: Bool { draft.project == nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var playlistResult: SpotifyLink.Result { SpotifyLink.parse(playlist) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $name)

                LabeledContent("Farbe") {
                    HStack(spacing: 8) {
                        ForEach(Array(ProjectPalette.colors.enumerated()), id: \.element) { index, hex in
                            colorButton(hex: hex, name: Self.colorNames[safe: index] ?? hex)
                        }
                    }
                }

                Picker("Art", selection: $isBusiness) {
                    Text("Business").tag(true)
                    Text("Privat").tag(false)
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Spotify-Playlist", text: $playlist, prompt: Text("Link, optional"))
                    if playlistResult == .invalid {
                        Text("Kein gültiger Spotify-Link (Playlist, Album oder Titel).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Anlegen" : "Sichern", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty || playlistResult == .invalid)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 460)
        .onAppear {
            // Vorbelegung erst hier, weil die genutzten Farben aus dem Store kommen.
            if colorHex.isEmpty {
                colorHex = ProjectPalette.next(after: store.projects.map(\.colorHex))
            }
        }
    }

    private func colorButton(hex: String, name: String) -> some View {
        let isSelected = hex.caseInsensitiveCompare(colorHex) == .orderedSame
        return Button {
            colorHex = hex
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 18, height: 18)
                .padding(3)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color.primary.opacity(0.6), lineWidth: 2)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func save() {
        let playlistURI: String?
        switch playlistResult {
        case .empty: playlistURI = nil
        case .valid(let uri): playlistURI = uri
        case .invalid: return
        }

        let existing = draft.project
        let project = Project(
            id: existing?.id ?? UUID(),
            name: trimmedName,
            colorHex: colorHex.isEmpty ? ProjectPalette.colors[0] : colorHex,
            isBusiness: isBusiness,
            isArchived: existing?.isArchived ?? false,
            sortOrder: existing?.sortOrder ?? store.nextSortOrder,
            playlistURI: playlistURI,
            createdAt: existing?.createdAt ?? .now
        )
        if store.saveProject(project) {
            dismiss()
        } else {
            errorMessage = store.consumeError()
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
