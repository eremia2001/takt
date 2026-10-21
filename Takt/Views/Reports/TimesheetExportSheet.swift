import SwiftUI
import TaktCore

// Sheet „Timesheet als PDF“ aus dem Export-Menü der Berichte: Zeitraum (vorbelegt mit dem
// gezeigten Berichtszeitraum), Umfang (alle Projekte, ein Kunde oder ein Projekt), Optionen und
// Kopfzeile. Darunter eine Vorschau in Worten (Einträge, Summe, Betrag); „PDF sichern…“ fragt nach
// dem Speicherort. Laufende Einträge kommen nie in den Nachweis – das Sheet weist darauf hin.

struct TimesheetExportSheet: View {
    @Environment(TaktStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    /// Wird nach dem Sichern mit dem Dateinamen aufgerufen (Bestätigung in den Berichten).
    var onSaved: (String) -> Void = { _ in }

    @State private var start: Date
    /// Letzter enthaltener Tag (gespeichert wird exklusiv: Mitternacht danach).
    @State private var lastDay: Date
    @State private var scope: TimesheetScope = .all
    @State private var clientName = ""
    @State private var entries: [TimeEntry] = []
    @State private var isSaving = false

    @AppStorage("timesheet.issuer") private var issuer = ""
    @AppStorage("timesheet.billableOnly") private var billableOnly = true
    @AppStorage("timesheet.showNotes") private var showNotes = true
    @AppStorage("timesheet.showTags") private var showTags = true
    @AppStorage("timesheet.daySubtotals") private var daySubtotals = false
    @AppStorage("timesheet.applyRounding") private var applyRounding = true

    private let calendar = Calendar.current

    init(initialInterval: DateInterval, onSaved: @escaping (String) -> Void = { _ in }) {
        self.onSaved = onSaved
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: initialInterval.start)
        let last = initialInterval.end > initialInterval.start ? initialInterval.end.addingTimeInterval(-1) : initialInterval.start
        _start = State(initialValue: start)
        _lastDay = State(initialValue: calendar.startOfDay(for: max(start, last)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Timesheet als PDF")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 20)
                .padding(.top, 18)

            Form {
                Section {
                    LabeledContent("Zeitraum") {
                        HStack(spacing: 6) {
                            DatePicker("Von", selection: startBinding, displayedComponents: .date)
                                .labelsHidden()
                            Text("–").foregroundStyle(.secondary)
                            DatePicker("Bis", selection: lastDayBinding, displayedComponents: .date)
                                .labelsHidden()
                        }
                    }
                    Picker("Für", selection: $scope) {
                        Text("Alle Projekte").tag(TimesheetScope.all)
                        if !clients.isEmpty {
                            Section("Kunden") {
                                ForEach(clients, id: \.self) { client in
                                    Text(client).tag(TimesheetScope.client(client))
                                }
                            }
                        }
                        Section("Projekte") {
                            ForEach(pickerProjects) { project in
                                Text(project.isArchived ? "\(project.name) (archiviert)" : project.name)
                                    .tag(TimesheetScope.project(project.id))
                            }
                        }
                    }
                }

                Section("Kopfzeile") {
                    TextField("Aussteller", text: $issuer, prompt: Text("Name, Firma, Anschrift"), axis: .vertical)
                        .lineLimit(1...4)
                    TextField("Kunde", text: $clientName, prompt: Text("Name des Kunden"))
                }

                Section("Optionen") {
                    Toggle("Nur abrechenbare Einträge", isOn: $billableOnly)
                    Toggle("Notizen anzeigen", isOn: $showNotes)
                    Toggle("Tags anzeigen", isOn: $showTags)
                    Toggle("Tagessummen anzeigen", isOn: $daySubtotals)
                    Toggle(isOn: $applyRounding) {
                        Text("Rundung anwenden")
                        Text(settings.rounding == .none
                             ? "In den Einstellungen ist keine Rundung gewählt"
                             : "Je Eintrag \(ReportsFormat.roundingHint(settings.rounding)) (Einstellungen)")
                    }
                    .disabled(settings.rounding == .none)
                }

                Section {
                    preview
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(false)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("PDF sichern…") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(timesheet.isEmpty || isSaving)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .padding(.top, 4)
        }
        .frame(width: 500, height: 640)
        .onAppear {
            reload()
            scope = defaultScope
            clientName = suggestedClientName(for: scope)
        }
        .onChange(of: start) { reload() }
        .onChange(of: lastDay) { reload() }
        .onChange(of: scope) { clientName = suggestedClientName(for: scope) }
    }

    // MARK: Vorschau

    private var preview: some View {
        let sheet = timesheet
        return VStack(alignment: .leading, spacing: 4) {
            if sheet.isEmpty {
                Text("Keine Einträge für diese Auswahl")
                    .foregroundStyle(.secondary)
            } else {
                Text(previewLine(sheet))
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                Text(amountLine(sheet))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ForEach(sheet.excludedRunning) { entry in
                Label(runningNote(entry), systemImage: "record.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text(fileName)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// „25 Einträge · 41:23 h · 42,75 h abgerechnet“
    private func previewLine(_ sheet: Timesheet) -> String {
        let count = sheet.lines.count == 1 ? "1 Eintrag" : "\(sheet.lines.count) Einträge"
        var parts = [count, "\(TimesheetPDF.hours(sheet.totalDuration)) h"]
        if sheet.options.rounding != .none {
            parts.append("\(TimesheetPDF.decimalHours(sheet.totalBilledDuration)) h abgerechnet")
        } else {
            parts.append("\(TimesheetPDF.decimalHours(sheet.totalDuration)) h")
        }
        return parts.joined(separator: " · ")
    }

    /// „Betrag 4.061,25 € (95,00 € / h)“ bzw. Hinweis ohne Satz.
    private func amountLine(_ sheet: Timesheet) -> String {
        guard let amount = sheet.amount else { return "Kein Stundensatz – das PDF zeigt nur Stunden" }
        let money = TimesheetPDF.money(amount, currencyCode: settings.currencyCode)
        if let rate = sheet.hourlyRate {
            return "Betrag \(money) (\(TimesheetPDF.money(rate, currencyCode: settings.currencyCode)) / h)"
        }
        return "Betrag \(money) (\(sheet.rateGroups.count) Stundensätze)"
    }

    private func runningNote(_ entry: TimeEntry) -> String {
        let name = store.projectsById[entry.projectId]?.name ?? "Eintrag"
        return "Laufender Eintrag „\(name)“ (seit \(TimesheetPDF.clock(entry.startedAt, calendar: calendar))) ist nicht enthalten"
    }

    // MARK: Daten

    private var interval: DateInterval {
        let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay.addingTimeInterval(86_400)
        return DateInterval(start: start, end: max(start, end))
    }

    private var allProjects: [Project] { Array(store.projectsById.values) }

    /// Aktive Projekte in eigener Reihenfolge, dazu archivierte mit Einträgen im Zeitraum.
    private var pickerProjects: [Project] {
        let used = Set(entries.map(\.projectId))
        let archived = store.archivedProjects.filter { used.contains($0.id) }
        return store.projects + archived.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var clients: [String] { Timesheet.clients(of: pickerProjects) }

    private var options: TimesheetOptions {
        TimesheetOptions(billableOnly: billableOnly, rounding: applyRounding ? settings.rounding : .none)
    }

    private var timesheet: Timesheet {
        Timesheet.make(
            entries: entries,
            projects: allProjects,
            interval: interval,
            scope: scope,
            options: options,
            defaultHourlyRate: settings.defaultHourlyRate,
            calendar: calendar
        )
    }

    private var document: TimesheetDocument {
        var projectName: String?
        if case .project(let id) = scope { projectName = store.projectsById[id]?.name }
        return TimesheetDocument(
            issuer: issuer,
            clientName: clientName.trimmingCharacters(in: .whitespacesAndNewlines),
            projectName: projectName,
            showNotes: showNotes,
            showTags: showTags,
            daySubtotals: daySubtotals,
            currencyCode: settings.currencyCode,
            createdAt: .now,
            calendar: calendar
        )
    }

    private var fileName: String {
        let label: String
        switch scope {
        case .all: label = clientName.isEmpty ? "Alle" : clientName
        case .client(let name): label = name
        case .project(let id): label = store.projectsById[id]?.name ?? "Projekt"
        }
        return TimesheetPDF.fileName(label: label, interval: interval, calendar: calendar)
    }

    /// Haben alle Einträge des Zeitraums denselben Kunden, ist er vorausgewählt.
    private var defaultScope: TimesheetScope {
        let used = Set(entries.map(\.projectId))
        let names = Timesheet.clients(of: allProjects.filter { used.contains($0.id) && $0.isBusiness })
        if names.count == 1, let only = names.first { return .client(only) }
        return .all
    }

    private func suggestedClientName(for scope: TimesheetScope) -> String {
        switch scope {
        case .all: ""
        case .client(let name): name
        case .project(let id): store.projectsById[id]?.client?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    private func reload() {
        entries = store.entries(in: interval)
        // Gewähltes archiviertes Projekt ohne Einträge im neuen Zeitraum: zurück auf „Alle“.
        if case .project(let id) = scope, !pickerProjects.contains(where: { $0.id == id }) { scope = .all }
        if case .client(let name) = scope,
           !clients.contains(where: { $0.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            scope = .all
        }
    }

    // MARK: Bindungen

    private var startBinding: Binding<Date> {
        Binding(
            get: { start },
            set: { value in
                start = calendar.startOfDay(for: value)
                if lastDay < start { lastDay = start }
            }
        )
    }

    private var lastDayBinding: Binding<Date> {
        Binding(
            get: { lastDay },
            set: { value in
                lastDay = calendar.startOfDay(for: value)
                if start > lastDay { start = lastDay }
            }
        )
    }

    // MARK: Sichern

    private func save() {
        let sheet = timesheet
        guard !sheet.isEmpty else { return }
        isSaving = true
        let data = TimesheetPDF.render(sheet, document: document)
        let name = fileName
        Task { @MainActor in
            defer { isSaving = false }
            do {
                if let url = try await TimesheetPDF.save(data, suggestedName: name) {
                    onSaved(url.lastPathComponent)
                    dismiss()
                }
            } catch {
                store.lastError = "Das PDF konnte nicht gespeichert werden: \(error.localizedDescription)"
            }
        }
    }
}
