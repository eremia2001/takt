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
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let draft: ProjectDraft

    @State private var name: String
    @State private var colorHex: String
    @State private var isBusiness: Bool
    @State private var playlist: String
    @State private var client: String
    @State private var rateText: String
    @State private var isBillable: Bool
    @State private var budgetText: String
    /// Solange `true`, folgt „Abrechenbar“ der Art (Business → ja, Privat → nein).
    /// Wird `false`, sobald der Schalter von Hand umgelegt wird.
    @State private var billableFollowsKind: Bool
    @State private var errorMessage: String?

    /// Namen der Palettenfarben (gleiche Reihenfolge wie `ProjectPalette.colors`) für VoiceOver.
    private static let colorNames = ["Blau", "Teal", "Indigo", "Orange", "Pink", "Grün", "Grau", "Braun"]

    init(draft: ProjectDraft) {
        self.draft = draft
        _name = State(initialValue: draft.project?.name ?? "")
        _colorHex = State(initialValue: draft.project?.colorHex ?? "")
        _isBusiness = State(initialValue: draft.project?.isBusiness ?? true)
        _playlist = State(initialValue: draft.project?.musicSource ?? "")
        _client = State(initialValue: draft.project?.client ?? "")
        _rateText = State(initialValue: HourlyRateField.text(for: draft.project?.hourlyRate))
        _budgetText = State(initialValue: BudgetFormat.hours(draft.project?.budgetHours))
        let isBusiness = draft.project?.isBusiness ?? true
        let isBillable = draft.project?.isBillable ?? isBusiness
        _isBillable = State(initialValue: isBillable)
        _billableFollowsKind = State(initialValue: isBillable == isBusiness)
    }

    private var isNew: Bool { draft.project == nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Bloße Namen gelten als Apple-Music-Playlist, wenn Apple Music bevorzugt ist.
    private var playlistResult: MusicLink.Result { MusicLink.parse(playlist, preferring: settings.musicProvider) }
    /// Unveränderte, bereits gespeicherte Musikquelle bleibt erlaubt, auch wenn die
    /// Erkennung sie nicht (mehr) versteht.
    private var playlistUnchanged: Bool { playlist == (draft.project?.musicSource ?? "") }
    private var playlistInvalid: Bool { playlistResult == .invalid && !playlistUnchanged }
    private var rateResult: HourlyRateField.Result { HourlyRateField.parse(rateText) }
    private var trimmedClient: String { client.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var budgetResult: HourlyRateField.Result { BudgetFormat.parse(budgetText) }

    /// Platzhalter im Stundensatz-Feld: der Standard-Stundensatz, falls gesetzt.
    private var ratePrompt: String {
        settings.defaultHourlyRate.map { "Standard \(HourlyRateField.text(for: $0))" } ?? "keiner"
    }

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
                .onChange(of: isBusiness) {
                    if billableFollowsKind { isBillable = isBusiness }
                }

                TextField("Kunde", text: $client, prompt: Text("optional"))

                HourlyRateField(
                    title: "Stundensatz",
                    text: $rateText,
                    currencyCode: settings.currencyCode,
                    prompt: ratePrompt,
                    hint: rateText.isEmpty && settings.defaultHourlyRate != nil ? "Leer = Standard-Stundensatz." : nil
                )

                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Stundenbudget") {
                        HStack(spacing: 6) {
                            TextField("Stundenbudget", text: $budgetText, prompt: Text("optional"))
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                            Text("h")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if budgetResult == .invalid {
                        Text("Bitte eine Stundenzahl über 0 eingeben, z. B. 40 oder 12,5.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !budgetText.isEmpty {
                        Text("Gezählt wird alle erfasste Zeit des Projekts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Abrechenbar", isOn: Binding(
                    get: { isBillable },
                    set: { newValue in
                        isBillable = newValue
                        billableFollowsKind = false
                    }
                ))

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Musik", text: $playlist, prompt: Text("Link oder Playlist-Name, optional"))
                    musicHint
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
                    .disabled(trimmedName.isEmpty || playlistInvalid || rateResult == .invalid || budgetResult == .invalid)
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

    /// Erkannte Musikquelle (Symbol + Art) oder Hinweis bei nicht erkannter Eingabe.
    @ViewBuilder
    private var musicHint: some View {
        switch playlistResult {
        case .empty:
            EmptyView()
        case .valid(let source):
            Label(MusicLink.summary(of: source), systemImage: source.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .invalid:
            if playlistInvalid {
                Text(MusicLink.invalidHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Gespeicherte Quelle wird nicht erkannt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        let musicSource: String?
        if playlistUnchanged {
            musicSource = draft.project?.musicSource
        } else {
            switch playlistResult {
            case .empty: musicSource = nil
            case .valid(let source): musicSource = source.storageString
            case .invalid: return
            }
        }

        let hourlyRate: Decimal?
        switch rateResult {
        case .empty: hourlyRate = nil
        case .valid(let rate): hourlyRate = rate
        case .invalid: return
        }

        let budgetHours: Decimal?
        switch budgetResult {
        case .empty: budgetHours = nil
        case .valid(let hours): budgetHours = hours
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
            musicSource: musicSource,
            client: trimmedClient.isEmpty ? nil : trimmedClient,
            hourlyRate: hourlyRate,
            isBillable: isBillable,
            budgetHours: budgetHours,
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
