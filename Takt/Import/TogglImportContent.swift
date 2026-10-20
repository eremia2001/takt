import AppKit
import SwiftUI
import TaktCore
import UniformTypeIdentifiers

/// Inhalt des Toggl-Import-Sheets in drei Schritten: Datei wählen → Vorschau mit Zuordnung
/// der Projekte → Ergebnis. Ohne Store-Abhängigkeit; `TogglImportSheet` verdrahtet ihn.
struct TogglImportContent: View {
    enum Step {
        case choose
        case preview(TogglImportPreview, fileName: String)
        case done(imported: Int, total: Int)
    }

    /// Alle Projekte (aktive zuerst, dann archivierte) als Ziele der Zuordnung.
    let projects: [Project]
    /// Vorschlag Toggl-Projekt → vorhandenes Projekt (`nil` = neu anlegen).
    var suggest: (TogglImportPreview) -> [String: UUID?] = { _ in [:] }
    /// Führt den Import aus: Anzahl neuer Einträge oder Fehlermeldung.
    var perform: (TogglImportPreview, [String: UUID?], Bool) -> Result<Int, ImportFailure> = { _, _, _ in .success(0) }
    var close: () -> Void = {}

    struct ImportFailure: Error { let message: String }

    @State private var step: Step
    @State private var mapping: [String: UUID?]
    @State private var markAsBusiness = true
    @State private var error: String?

    @Environment(\.colorScheme) private var scheme
    private var theme: DesignTheme { DesignTheme(scheme: scheme) }

    init(
        projects: [Project],
        initialStep: Step = .choose,
        initialMapping: [String: UUID?] = [:],
        suggest: @escaping (TogglImportPreview) -> [String: UUID?] = { _ in [:] },
        perform: @escaping (TogglImportPreview, [String: UUID?], Bool) -> Result<Int, ImportFailure> = { _, _, _ in .success(0) },
        close: @escaping () -> Void = {}
    ) {
        self.projects = projects
        self.suggest = suggest
        self.perform = perform
        self.close = close
        _step = State(initialValue: initialStep)
        _mapping = State(initialValue: initialMapping)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Aus Toggl importieren")
                    .font(.system(size: 17, weight: .semibold))
                Text(stepTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.tertiary)
            }
            .padding(.bottom, 16)

            switch step {
            case .choose:
                chooseStep
            case .preview(let preview, let fileName):
                previewStep(preview, fileName: fileName)
            case .done(let imported, let total):
                doneStep(imported: imported, total: total)
            }
        }
        .padding(24)
        .frame(width: 600)
        .background(theme.window)
    }

    private var stepTitle: String {
        switch step {
        case .choose: "Schritt 1 von 3 · Datei wählen"
        case .preview: "Schritt 2 von 3 · Vorschau und Zuordnung"
        case .done: "Schritt 3 von 3 · Fertig"
        }
    }

    // MARK: Schritt 1

    private var chooseStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("In Toggl Track unter „Reports → Detailed“ den Zeitraum wählen und als CSV exportieren. Takt liest Start, Ende bzw. Dauer, Projekt, Kunde, Beschreibung und „Billable“.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Nichts wird gespeichert, bevor du die Vorschau bestätigst. Bereits vorhandene Einträge (gleicher Start und gleiches Ende im selben Projekt) werden übersprungen.")
                .font(.system(size: 12))
                .foregroundStyle(theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            errorText
            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel, action: close)
                    .keyboardShortcut(.cancelAction)
                Button("CSV-Datei wählen …", action: chooseFile)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
    }

    // MARK: Schritt 2

    private func previewStep(_ preview: TogglImportPreview, fileName: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                stat("Einträge", "\(preview.entries.count)")
                stat("Zeitraum", rangeTitle(preview))
                stat("Gesamt", DurationFormat.hourMinute(preview.entries.reduce(0) { $0 + $1.duration }))
            }
            VStack(alignment: .leading, spacing: 4) {
                Label(fileName, systemImage: "doc.text")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if preview.skipped > 0 {
                    Text(preview.skipped == 1 ? "1 Zeile übersprungen" : "\(preview.skipped) Zeilen übersprungen")
                        .font(.system(size: 12, weight: .medium))
                }
                if !preview.warnings.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(preview.warnings.enumerated()), id: \.offset) { _, warning in
                                Text(warning)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: 64)
                }
            }

            mappingTable(preview)

            Toggle("Neue Projekte als Business anlegen", isOn: $markAsBusiness)
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
            errorText
            HStack {
                Button("Andere Datei …", action: chooseFile)
                Spacer()
                Button("Abbrechen", role: .cancel, action: close)
                    .keyboardShortcut(.cancelAction)
                Button(preview.entries.count == 1 ? "1 Eintrag importieren" : "\(preview.entries.count) Einträge importieren") {
                    runImport(preview)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(preview.entries.isEmpty)
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.tertiary)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.hairline, lineWidth: 1))
    }

    private func mappingTable(_ preview: TogglImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Toggl-Projekt")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Takt-Projekt")
                    .frame(width: 230, alignment: .leading)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.tertiary)
            .padding(.bottom, 6)

            // Bis sechs Projekte ohne Rollen (bündig mit der Kopfzeile), darüber rollbar.
            if preview.newProjects.count > 6 {
                ScrollView { mappingRows(preview) }
                    .frame(height: 290)
            } else {
                mappingRows(preview)
            }
        }
    }

    private func mappingRows(_ preview: TogglImportPreview) -> some View {
        VStack(spacing: 0) {
            ForEach(preview.newProjects, id: \.self) { name in
                Rectangle().fill(theme.hairline).frame(height: 1)
                mappingRow(name, preview: preview)
            }
        }
    }

    private func mappingRow(_ name: String, preview: TogglImportPreview) -> some View {
        let items = preview.entries.filter { $0.projectName == name }
        let total = items.reduce(0) { $0 + $1.duration }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text("\(items.count == 1 ? "1 Eintrag" : "\(items.count) Einträge") · \(DurationFormat.hourMinute(total))")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Picker("Takt-Projekt für \(name)", selection: binding(for: name)) {
                Text("Neu anlegen").tag(UUID?.none)
                Divider()
                ForEach(projects) { project in
                    Text(project.isArchived ? "\(project.name) (Archiv)" : project.name)
                        .tag(Optional(project.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 230, alignment: .leading)
        }
        .padding(.vertical, 7)
    }

    private func binding(for name: String) -> Binding<UUID?> {
        Binding(
            get: { mapping[name] ?? nil },
            set: { mapping[name] = .some($0) }
        )
    }

    private func rangeTitle(_ preview: TogglImportPreview) -> String {
        guard let first = preview.entries.map(\.start).min(),
              let last = preview.entries.map(\.end).max() else { return "–" }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: first)
        // Ende exklusiv: Mitternacht nach dem letzten Tag (ein Ende um 0:00 gehört zum Vortag).
        let lastDay = calendar.startOfDay(for: last > first ? last.addingTimeInterval(-1) : last)
        let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay.addingTimeInterval(86_400)
        return ReportPeriod.custom(DateInterval(start: start, end: max(end, start.addingTimeInterval(1))))
            .title(calendar: calendar)
    }

    // MARK: Schritt 3

    private func doneStep(imported: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(imported)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(imported == 1 ? "Eintrag importiert" : "Einträge importiert")
                    .font(.system(size: 15, weight: .semibold))
            }
            if total > imported {
                let skipped = total - imported
                Text(skipped == 1
                     ? "1 Eintrag war bereits vorhanden und wurde übersprungen."
                     : "\(skipped) Einträge waren bereits vorhanden und wurden übersprungen.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Schließen", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Aktionen

    @ViewBuilder
    private var errorText: some View {
        if let error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Toggl-Export wählen"
        panel.prompt = "Öffnen"
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    private func load(_ url: URL) {
        do {
            let text = try Self.readText(url)
            let preview = try TogglImport.parse(csv: text)
            error = nil
            mapping = suggest(preview)
            step = .preview(preview, fileName: url.lastPathComponent)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func runImport(_ preview: TogglImportPreview) {
        switch perform(preview, mapping, markAsBusiness) {
        case .success(let count):
            error = nil
            step = .done(imported: count, total: preview.entries.count)
        case .failure(let failure):
            error = failure.message
        }
    }

    /// Liest die Datei als UTF-8 (Toggl-Standard), ersatzweise als Windows-1252.
    static func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .windowsCP1252) { return text }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
}
