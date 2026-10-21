import EventKit
import SwiftUI
import TaktCore

/// Abschnitt „Kalender“: Zugriff, Termine in „Heute“, sichtbare Kalender, Spiegelung erfasster
/// Zeiten in den Kalender „Takt“ und Regeln Termin → Projekt. EventKit liegt im `CalendarService`,
/// Regeln im Store.
struct CalendarSettingsSection: View {
    /// Optional, damit die Einstellungen auch ohne verdrahteten Dienst öffnen.
    @Environment(CalendarService.self) private var calendarService: CalendarService?

    var body: some View {
        if let calendarService {
            CalendarSettingsContent(service: calendarService)
        } else {
            Section("Kalender") {
                Text("Die Kalender-Anbindung ist in dieser Version nicht aktiv.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CalendarSettingsContent: View {
    let service: CalendarService
    @Environment(AppSettings.self) private var settings

    @State private var isDisableDialogShown = false
    @State private var isRequesting = false

    var body: some View {
        @Bindable var settings = settings
        Section {
            PermissionRow(
                symbol: "calendar",
                title: "Kalender",
                state: accessState,
                purpose: "Damit Takt Termine in „Heute“ zeigen und erfasste Zeiten in einen eigenen Kalender „Takt“ eintragen kann. Takt ändert keine anderen Kalender.",
                request: isRequesting ? nil : {
                    isRequesting = true
                    Task {
                        await service.requestAccess()
                        isRequesting = false
                    }
                },
                openSettings: { service.openPrivacySettings() }
            )
            Toggle(isOn: $settings.calendarShowEvents) {
                Text("Termine in „Heute“ anzeigen")
                Text("Zeigt heutige Termine als Spur über der Tagesleiste und als Liste – mit „Als Eintrag“, um einen Termin als Zeit zu übernehmen.")
            }
            .disabled(!service.hasFullAccess)
        } header: {
            Text("Zugriff")
        }

        if service.hasFullAccess {
            visibleCalendarsSection
            mirrorSection
            Section {
                CalendarRuleList()
            } header: {
                Text("Regeln Termin → Projekt")
            } footer: {
                Text("Eine Regel ordnet Termine einem Projekt zu, etwa für „Als Eintrag“ und den Hinweis „Termin läuft“. Es gilt die erste passende Regel von oben; Reihenfolge per Ziehen am Griff ≡.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mit Zugriff kannst du hier:")
                        .font(.callout.weight(.medium))
                    Label("Termine in „Heute“ sehen und mit einem Klick als Eintrag übernehmen", systemImage: "calendar.day.timeline.left")
                    Label("Erfasste Zeiten automatisch in einen Kalender „Takt“ eintragen", systemImage: "arrow.triangle.2.circlepath")
                    Label("Termine per Regel Projekten zuordnen, z. B. Titel enthält „Gerlach“ → Kundenportal", systemImage: "arrow.right.circle")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
            } header: {
                Text("Noch kein Zugriff")
            }
        }
    }

    /// Kalender-Zugriff als einheitlicher Freigabe-Status.
    private var accessState: PermissionState {
        if service.hasFullAccess { return .granted() }
        if service.canRequestAccess { return isRequesting ? .checking : .notDetermined() }
        return .denied(service.statusText.components(separatedBy: " – ").first ?? "Abgelehnt")
    }

    // MARK: Sichtbare Kalender

    private var visibleCalendarsSection: some View {
        Section {
            ForEach(service.calendars.filter { !service.isMirrorCalendar($0) }, id: \.calendarIdentifier) { calendar in
                Toggle(isOn: Binding(
                    get: { service.isVisible(calendar) },
                    set: { service.setVisible($0, calendar: calendar) }
                )) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(Color(cgColor: calendar.cgColor))
                            .frame(width: 8, height: 8)
                        Text(calendar.title)
                        if let source = calendar.source?.title {
                            Text(source)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(!settings.calendarShowEvents)
            }
        } header: {
            Text("Angezeigte Kalender")
        } footer: {
            Text("Nur angehakte Kalender erscheinen in „Heute“. Der Kalender „Takt“ fehlt hier bewusst – er enthält deine Einträge selbst.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Spiegelung

    private var mirrorSection: some View {
        Section {
            Toggle(isOn: mirrorBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Erfasste Zeiten in den Kalender „Takt“ eintragen")
                    Text("Legt einen eigenen Kalender „Takt“ an, mit einem Ereignis je Eintrag der letzten 30 Tage – so siehst du deine Zeiten auch in der Kalender-App. Andere Kalender bleiben unberührt.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Picker(selection: sourceBinding) {
                if service.mirrorSourceID == nil {
                    Text("Bitte wählen").tag(String?.none)
                }
                ForEach(service.mirrorSources) { source in
                    Text(source.label).tag(String?.some(source.id))
                }
            } label: {
                Text("Konto")
                Text("Wo der Kalender „Takt“ liegt, z. B. iCloud (dann auch auf dem iPhone) oder „Auf meinem Mac“.")
            }
            .disabled(service.mirrorSources.isEmpty)
            LabeledContent {
                Stepper {
                    Text("\(settings.calendarMirrorMinimumMinutes) Min")
                        .monospacedDigit()
                } onIncrement: {
                    settings.calendarMirrorMinimumMinutes = Self.minimumSteps.first { $0 > settings.calendarMirrorMinimumMinutes } ?? 240
                } onDecrement: {
                    settings.calendarMirrorMinimumMinutes = Self.minimumSteps.last { $0 < settings.calendarMirrorMinimumMinutes } ?? 1
                }
            } label: {
                Text("Mindestdauer")
                Text("Kürzere Einträge werden nicht eingetragen. Standard: 5 Min")
            }
            LabeledContent {
                Button("Jetzt spiegeln") { service.mirrorNow() }
                    .disabled(!settings.calendarMirrorEnabled || service.mirrorCalendar == nil)
                    .help("Gleicht den Kalender „Takt“ sofort ab – sonst geschieht das nach jeder Änderung und alle 30 Minuten von selbst")
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(countText)
                    if let last = service.lastMirrorAt {
                        Text("zuletzt \(ClockFormat.time(last))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let error = service.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Zeiten in Kalender spiegeln")
        }
        .confirmationDialog(
            "Spiegelung ausschalten?",
            isPresented: $isDisableDialogShown
        ) {
            Button("Ereignisse behalten") { service.disableMirror(deleteEvents: false) }
            Button("Ereignisse löschen", role: .destructive) { service.disableMirror(deleteEvents: true) }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Ereignisse im Kalender ‚Takt‘ behalten oder löschen? Andere Kalender bleiben unberührt.")
        }
    }

    /// Stufen des Mindestdauer-Steppers (1–240 min).
    private static let minimumSteps = [1, 2, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240]

    private var countText: String {
        switch service.mirroredCount {
        case 0: "Noch keine Ereignisse gespiegelt"
        case 1: "1 Ereignis gespiegelt"
        default: "\(service.mirroredCount) Ereignisse gespiegelt"
        }
    }

    /// Einschalten legt bei Bedarf den Kalender an; Ausschalten fragt nach den Ereignissen.
    private var mirrorBinding: Binding<Bool> {
        Binding(
            get: { settings.calendarMirrorEnabled },
            set: { isOn in
                if isOn {
                    service.enableMirror()
                } else {
                    isDisableDialogShown = true
                }
            }
        )
    }

    private var sourceBinding: Binding<String?> {
        Binding(
            get: { service.mirrorSourceID },
            set: { id in
                guard let id, id != service.mirrorSourceID else { return }
                service.useMirrorSource(id)
            }
        )
    }
}

// MARK: - Regeln

/// Tabelle der Kalender-Regeln: Art, Muster, Projekt; − je Zeile, + in der Zeile darunter,
/// Reihenfolge per Ziehen am Griff.
private struct CalendarRuleList: View {
    @Environment(TaktStore.self) private var store

    @State private var newKind: CalendarRuleKind = .titleContains
    @State private var newPattern = ""
    @State private var newProjectId: UUID?
    @State private var dropTarget: UUID?

    var body: some View {
        if store.calendarRules.isEmpty {
            // Beispielregel als Platzhalter: zeigt, wie eine Zeile aussieht.
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .frame(width: 14)
                Text("Titel enthält")
                    .frame(width: 118, alignment: .leading)
                Text("„Gerlach“")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right")
                    .font(.caption)
                Text("Kundenportal")
                    .frame(width: 112, alignment: .leading)
            }
            .foregroundStyle(.tertiary)
            .help("Beispiel – lege unten eine eigene Regel an")
            .accessibilityLabel("Beispielregel: Titel enthält Gerlach, Projekt Kundenportal")
            Text("Noch keine Regeln. So sähe eine aus – unten Art, Muster und Projekt wählen und + klicken.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        ForEach(store.calendarRules) { rule in
            CalendarRuleRow(rule: rule)
                .overlay(alignment: .top) {
                    if dropTarget == rule.id {
                        Rectangle().fill(Color.accentColor).frame(height: 2).offset(y: -5)
                    }
                }
                .dropDestination(for: String.self) { items, _ in
                    defer { dropTarget = nil }
                    guard let text = items.first, let id = UUID(uuidString: text) else { return false }
                    return move(id, before: rule.id)
                } isTargeted: { targeted in
                    if targeted { dropTarget = rule.id } else if dropTarget == rule.id { dropTarget = nil }
                }
        }
        addRow
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            // Platz des Griffs, damit die Spalten mit den Regeln fluchten.
            Color.clear.frame(width: 14, height: 1)
            Picker("Art", selection: $newKind) {
                ForEach(CalendarRuleKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .labelsHidden()
            .frame(width: 118)
            TextField("Muster", text: $newPattern, prompt: Text(CalendarRuleRow.placeholder(newKind)))
                .labelsHidden()
                .onSubmit(add)
            Picker("Projekt", selection: $newProjectId) {
                Text("Projekt …").tag(UUID?.none)
                ForEach(store.projects) { project in
                    Text(project.name).tag(UUID?.some(project.id))
                }
            }
            .labelsHidden()
            .frame(width: 130)
            Button(action: add) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(!canAdd)
            .help("Regel hinzufügen")
            .accessibilityLabel("Regel hinzufügen")
        }
    }

    private var canAdd: Bool {
        newProjectId != nil && !newPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func add() {
        guard canAdd, let projectId = newProjectId else { return }
        if store.addCalendarRule(kind: newKind, pattern: newPattern, projectId: projectId) {
            newPattern = ""
        }
    }

    /// Verschiebt die Regel `id` an die Stelle der Regel `target`.
    private func move(_ id: UUID, before target: UUID) -> Bool {
        let rules = store.calendarRules
        guard id != target,
              let from = rules.firstIndex(where: { $0.id == id }),
              let to = rules.firstIndex(where: { $0.id == target }) else { return false }
        // `move(fromOffsets:toOffset:)`: nach unten zählt die Position hinter dem Ziel.
        store.reorderCalendarRules(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        return true
    }
}

/// Eine Regel: Griff, Art, Muster (wird bei Enter bzw. Verlassen gesichert), Projekt, −.
private struct CalendarRuleRow: View {
    let rule: CalendarRule
    @Environment(TaktStore.self) private var store

    @State private var pattern: String
    @FocusState private var isPatternFocused: Bool

    init(rule: CalendarRule) {
        self.rule = rule
        _pattern = State(initialValue: rule.pattern)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .frame(width: 14)
                .contentShape(Rectangle())
                .draggable(rule.id.uuidString) {
                    Text(rule.pattern).padding(4)
                }
                .help("Ziehen, um die Reihenfolge zu ändern")
            Picker("Art", selection: Binding(
                get: { rule.kind },
                set: { kind in
                    var changed = rule
                    changed.kind = kind
                    store.saveCalendarRule(changed)
                }
            )) {
                ForEach(CalendarRuleKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .labelsHidden()
            .frame(width: 118)
            TextField("Muster", text: $pattern, prompt: Text(Self.placeholder(rule.kind)))
                .labelsHidden()
                .focused($isPatternFocused)
                .onSubmit(savePattern)
                .onChange(of: isPatternFocused) { _, focused in
                    if !focused { savePattern() }
                }
                .onChange(of: rule.pattern) { _, stored in
                    if !isPatternFocused { pattern = stored }
                }
            Picker("Projekt", selection: Binding(
                get: { rule.projectId },
                set: { projectId in
                    var changed = rule
                    changed.projectId = projectId
                    store.saveCalendarRule(changed)
                }
            )) {
                ForEach(projectOptions) { project in
                    Text(project.isArchived ? "\(project.name) (archiviert)" : project.name).tag(project.id)
                }
            }
            .labelsHidden()
            .frame(width: 130)
            Button {
                store.deleteCalendarRule(rule)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Regel löschen")
            .accessibilityLabel("Regel löschen")
        }
    }

    /// Aktive Projekte, dazu das der Regel, falls es archiviert ist.
    private var projectOptions: [Project] {
        var options = store.projects
        if !options.contains(where: { $0.id == rule.projectId }), let current = store.project(id: rule.projectId) {
            options.append(current)
        }
        return options
    }

    private func savePattern() {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != rule.pattern else { return }
        guard !trimmed.isEmpty else {
            pattern = rule.pattern
            return
        }
        var changed = rule
        changed.pattern = trimmed
        store.saveCalendarRule(changed)
    }

    static func placeholder(_ kind: CalendarRuleKind) -> String {
        switch kind {
        case .calendarName: "z. B. Arbeit"
        case .titleContains: "z. B. Gerlach"
        case .attendeeDomain: "z. B. acme.de"
        }
    }
}
