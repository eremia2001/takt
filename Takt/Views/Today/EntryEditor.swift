import SwiftUI
import TaktCore

/// Zu bearbeitender bzw. neuer Eintrag für das Sheet.
struct EntryDraft: Identifiable {
    let entry: TimeEntry
    let isNew: Bool
    /// Projekt noch offen (z. B. Termin ohne passende Regel): Der Picker startet leer und
    /// verlangt eine Auswahl; `entry.projectId` ist dann nur ein Platzhalter.
    var needsProject = false

    var id: UUID { entry.id }
}

/// Sheet zum Anlegen und Bearbeiten eines Eintrags.
struct EntryEditor: View {
    @Environment(TaktStore.self) private var store
    @Environment(CalendarService.self) private var calendarService: CalendarService?
    @Environment(\.dismiss) private var dismiss

    let draft: EntryDraft

    @State private var projectId: UUID?
    @State private var startedAt: Date
    @State private var endedAt: Date
    @State private var nextStep: String
    @State private var tag: String
    @State private var errorMessage: String?
    @State private var isDeleteConfirmationShown = false

    init(draft: EntryDraft) {
        self.draft = draft
        _projectId = State(initialValue: draft.needsProject ? nil : draft.entry.projectId)
        _startedAt = State(initialValue: draft.entry.startedAt)
        _endedAt = State(initialValue: draft.entry.endedAt ?? .now)
        _nextStep = State(initialValue: draft.entry.nextStep ?? "")
        _tag = State(initialValue: draft.entry.tag ?? "")
    }

    /// Ein laufender Eintrag behält sein offenes Ende.
    private var isRunning: Bool { !draft.isNew && draft.entry.isRunning }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("Projekt", selection: $projectId) {
                    if projectId == nil {
                        Text("Bitte wählen").tag(UUID?.none)
                    }
                    ForEach(projectOptions) { project in
                        Text(project.name).tag(UUID?.some(project.id))
                    }
                }

                DatePicker("Beginn", selection: $startedAt, displayedComponents: [.date, .hourAndMinute])

                if isRunning {
                    LabeledContent("Ende", value: "läuft noch")
                } else {
                    DatePicker("Ende", selection: $endedAt, displayedComponents: [.date, .hourAndMinute])
                }

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Nächster Schritt", text: $nextStep, prompt: Text("optional"))
                        .help(TermHelp.nextStep)
                    Text("Notiz, die beim nächsten Start dieses Projekts angezeigt wird.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Tag", text: $tag, prompt: Text("optional, z. B. Meeting"))
                    Text("Ein Stichwort zum Eintrag; Berichte schlüsseln die Projektzeit danach auf.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Vorschläge: zuerst Tags dieses Projekts, zuletzt genutzte zuerst; Klick übernimmt.
                let suggestions = store.tagSuggestions(projectId: projectId ?? draft.entry.projectId, prefix: tag)
                if !TagSuggestionChips.visible(suggestions, text: tag).isEmpty {
                    TagSuggestionChips(text: $tag, suggestions: suggestions)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if let validationMessage {
                    Text(validationMessage)
                        .foregroundStyle(.secondary)
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            HStack {
                if !draft.isNew {
                    Button("Löschen …", role: .destructive) {
                        isDeleteConfirmationShown = true
                    }
                }
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(draft.isNew ? "Hinzufügen" : "Sichern", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(validationMessage != nil)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 440)
        .navigationTitle(draft.isNew ? "Neuer Eintrag" : "Eintrag bearbeiten")
        .confirmationDialog("Eintrag löschen?", isPresented: $isDeleteConfirmationShown) {
            Button("Löschen", role: .destructive, action: delete)
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Der Eintrag wird endgültig entfernt.")
        }
    }

    /// Aktive Projekte, dazu das bisherige Projekt, falls es inzwischen archiviert ist.
    private var projectOptions: [Project] {
        var options = store.projects
        if !options.contains(where: { $0.id == draft.entry.projectId }),
           let current = store.project(id: draft.entry.projectId) {
            options.append(current)
        }
        return options
    }

    private var validationMessage: String? {
        if projectId == nil { return "Bitte ein Projekt wählen." }
        if isRunning {
            return startedAt > .now ? "Der Beginn liegt in der Zukunft." : nil
        }
        return endedAt < startedAt ? "Das Ende liegt vor dem Beginn." : nil
    }

    private func save() {
        let trimmed = nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        // Vom Entwurf ausgehen, damit Felder ohne Eingabe hier (z. B. „abrechenbar“) erhalten bleiben.
        guard let projectId else { return }
        var entry = draft.entry
        entry.projectId = projectId
        entry.startedAt = startedAt
        entry.endedAt = isRunning ? nil : endedAt
        entry.nextStep = trimmed.isEmpty ? nil : trimmed
        entry.tag = TimeEntry.normalizedTag(tag)
        let success = draft.isNew ? store.addEntry(entry) : store.updateEntry(entry)
        finish(success)
    }

    private func delete() {
        // Gespiegeltes Kalenderereignis vor dem Eintrag entfernen (die Verknüpfung fällt per CASCADE).
        calendarService?.willDelete(entryId: draft.entry.id)
        finish(store.deleteEntry(draft.entry))
    }

    /// Bei Erfolg schließen, sonst den Fehler im Sheet zeigen (statt im Hauptfenster).
    private func finish(_ success: Bool) {
        if success {
            dismiss()
        } else {
            errorMessage = store.consumeError()
        }
    }
}
