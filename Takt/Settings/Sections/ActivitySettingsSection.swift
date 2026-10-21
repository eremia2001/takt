import AppKit
import SwiftUI
import TaktCore

/// Reiter „Aktivität“: Projektvorschläge aus App, Fenster und Git-Repository.
/// Schalter und Schwellen liegen in `AppSettings` (`activity…`), Regeln und Proben im Store.
/// Der `ActivityMonitor` ist optional in der Umgebung: Ohne ihn zeigt „Zuletzt erkannt“ nur
/// Gespeichertes (nicht den laufenden Abschnitt).
struct ActivitySettingsSection: View {
    @Environment(TaktStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(ActivityMonitor.self) private var monitor: ActivityMonitor?

    @State private var isTrusted = ActivityProbe.isTrusted
    @State private var recent: [ActivitySample] = []
    @State private var showsAddRule = false
    /// Probe, aus der gerade eine Regel angelegt wird („Regel daraus“).
    @State private var ruleSource: ActivitySample?

    var body: some View {
        @Bindable var settings = settings
        let enabled = settings.activitySuggestionsEnabled

        Section("Aktivität") {
            Toggle(isOn: $settings.activitySuggestionsEnabled) {
                Text("Projektvorschläge aus Aktivität")
                Text("Takt erkennt an App, Fenster und Git-Repository, woran du arbeitest, und meldet sich, wenn der Timer nicht dazu passt.")
            }

            PermissionRow(
                symbol: "accessibility",
                title: "Bedienungshilfen",
                state: isTrusted ? .granted() : .notDetermined("Nicht erlaubt"),
                purpose: isTrusted
                    ? "Takt liest Fenstertitel und erkennt darin Git-Repositorys. Es werden keine Eingaben mitgelesen."
                    : "Nötig, um Fenstertitel und Git-Repositorys zu lesen. Ohne Freigabe erkennt Takt nur die App (z. B. „Xcode“); Regeln „App“ funktionieren trotzdem.",
                request: { ActivityProbe.requestTrust() },
                openSettings: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            )
            if enabled {
                NotificationPermissionRow(
                    purpose: "Für den Vorschlag „Wechseln zu …“, wenn der Timer nicht zur Arbeit passt."
                )
            }

            Stepper(value: $settings.activityMismatchMinutes, in: 1...120) {
                Text("Nachfragen nach \(settings.activityMismatchMinutes) Min")
                    .monospacedDigit()
                Text("So lange muss die Arbeit überwiegend (70 %) zu einem anderen Projekt passen. Standard: 10 Min")
            }
            .disabled(!enabled)

            Toggle(isOn: $settings.activityAutoStartEnabled) {
                Text("Automatisch starten")
                Text("Läuft kein Timer, startet Takt das erkannte Projekt selbst und sagt per Mitteilung Bescheid. Sinnvoll, wenn du oft vergisst zu starten.")
            }
            .disabled(!enabled)
        }

        Section {
            if store.activityRules.isEmpty {
                // Beispielregel als Platzhalter: zeigt, wie eine Zeile aussieht.
                HStack(spacing: 8) {
                    Text("Repo-Pfad")
                    Text("~/dev/kundenportal")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                    Text("Kundenportal")
                }
                .foregroundStyle(.tertiary)
                .help("Beispiel – eigene Regel mit + oben rechts oder „Regel daraus“ unten anlegen")
                .accessibilityLabel("Beispielregel: Repo-Pfad ~/dev/kundenportal, Projekt Kundenportal")
                Text("Noch keine Regeln. Ohne Regel ordnet Takt Repositorys mit ähnlichem Namen zu, z. B. „eventbuster-app“ → EventBuster. Eigene Regeln mit + oder „Regel daraus“.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let rules = store.activityRules
                ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                    ActivityRuleRow(
                        rule: rule,
                        isFirst: index == 0,
                        isLast: index == rules.count - 1,
                        move: { offset in move(index: index, by: offset) }
                    )
                }
            }
        } header: {
            HStack {
                Text("Regeln")
                Spacer()
                Button {
                    showsAddRule = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Regel hinzufügen")
                .disabled(store.projects.isEmpty)
                .popover(isPresented: $showsAddRule, arrowEdge: .bottom) {
                    ActivityRuleEditor(
                        title: "Neue Regel",
                        kind: .repoPath,
                        pattern: "",
                        projectId: store.projects.first?.id,
                        onDone: { showsAddRule = false }
                    )
                    .environment(store)
                }
            }
        } footer: {
            Text("Eine Regel legt fest, welches Projekt zu einer App, einem Fenstertitel oder einem Ordner gehört. Es gilt die erste passende Regel von oben (▲/▼ ordnet um).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section {
            if recent.isEmpty {
                Text(enabled ? "Noch nichts erkannt." : "Schalte die Projektvorschläge ein, damit Takt Aktivität erkennt.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recent) { sample in
                    recentRow(sample)
                }
            }
        } header: {
            Text("Zuletzt erkannt")
        } footer: {
            Label("Alles bleibt auf diesem Mac: App, Fenstertitel und Repository werden 30 Tage lokal gespeichert und dann automatisch gelöscht.", systemImage: "lock")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .task(id: enabled) {
            // Solange der Reiter sichtbar ist: Freigabe und letzte Proben aktuell halten.
            while !Task.isCancelled {
                reload()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    // MARK: Zuletzt erkannt

    private func recentRow(_ sample: ActivitySample) -> some View {
        let isCurrent = monitor?.current?.id == sample.id
        let project = sample.projectId.flatMap { store.projectsById[$0] }
        let place = sample.repoPath.map { ActivityHeuristics.abbreviate($0) } ?? sample.windowTitle

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(ClockFormat.time(sample.startedAt))
                    .monospacedDigit()
                Text(isCurrent ? "läuft" : Self.minutes(sample.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(width: 42, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(ActivityAppNames.name(for: sample.bundleID))
                    .lineLimit(1)
                Text(place ?? "–")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .help(sample.windowTitle ?? sample.bundleID)

            Spacer(minLength: 8)

            if let project {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(hex: project.colorHex))
                        .frame(width: 7, height: 7)
                    Text(project.name)
                        .lineLimit(1)
                }
                .font(.callout)
                .frame(maxWidth: 120, alignment: .trailing)
            } else {
                Text("kein Projekt")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }

            Button("Regel daraus") { ruleSource = sample }
                .controlSize(.small)
                .help("Legt eine Regel an, damit diese Arbeit künftig einem Projekt zugeordnet wird")
                .disabled(store.projects.isEmpty)
                .popover(isPresented: Binding(
                    get: { ruleSource?.id == sample.id },
                    set: { if !$0 { ruleSource = nil } }
                ), arrowEdge: .trailing) {
                    let suggestion = Self.ruleSuggestion(from: sample)
                    ActivityRuleEditor(
                        title: "Regel aus Aktivität",
                        kind: suggestion.kind,
                        pattern: suggestion.pattern,
                        projectId: project.flatMap { $0.isArchived ? nil : $0.id } ?? store.projects.first?.id,
                        onDone: { ruleSource = nil }
                    )
                    .environment(store)
                }
        }
    }

    /// Repository, sonst App – ein Fenstertitel ist meist zu flüchtig für eine Regel.
    static func ruleSuggestion(from sample: ActivitySample) -> (kind: ActivityRuleKind, pattern: String) {
        if let repo = sample.repoPath { return (.repoPath, ActivityHeuristics.abbreviate(repo)) }
        return (.bundleID, sample.bundleID)
    }

    private static func minutes(_ duration: TimeInterval) -> String {
        duration < 60 ? "< 1 min" : "\(Int(duration / 60)) min"
    }

    // MARK: Aktionen

    private func reload() {
        let trusted = ActivityProbe.isTrusted
        if trusted != isTrusted { isTrusted = trusted }
        monitor?.refreshTrust()
        let samples: [ActivitySample]
        if let monitor {
            samples = monitor.recentSamples(limit: 10)
        } else {
            let now = Date()
            samples = Array(store.activitySamples(in: DateInterval(start: now.addingTimeInterval(-24 * 3600), end: now))
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(10))
        }
        if samples != recent { recent = samples }
    }

    private func move(index: Int, by offset: Int) {
        let destination = index + offset
        guard destination >= 0, destination < store.activityRules.count else { return }
        // `onMove`-Semantik: Ziel ist die Position vor dem Element, beim Abwärtsschieben +1.
        store.reorderActivityRules(fromOffsets: IndexSet(integer: index), toOffset: offset > 0 ? destination + 1 : destination)
    }
}

// MARK: - Regel-Zeile

/// Eine Regel: Reihenfolge, Art, Muster (wird beim Verlassen des Feldes gespeichert), Projekt, Löschen.
private struct ActivityRuleRow: View {
    @Environment(TaktStore.self) private var store

    let rule: ActivityRule
    let isFirst: Bool
    let isLast: Bool
    let move: (Int) -> Void

    @State private var pattern = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 0) {
                Button { move(-1) } label: { Image(systemName: "chevron.up").font(.system(size: 9, weight: .semibold)) }
                    .disabled(isFirst)
                    .help("Nach oben")
                Button { move(1) } label: { Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)) }
                    .disabled(isLast)
                    .help("Nach unten")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)

            Picker("Art", selection: Binding(
                get: { rule.kind },
                set: { kind in
                    var updated = rule
                    updated.kind = kind
                    store.saveActivityRule(updated)
                }
            )) {
                ForEach(ActivityRuleKind.allCases, id: \.self) { kind in
                    Text(ActivityRuleEditor.shortTitle(kind)).tag(kind)
                }
            }
            .labelsHidden()
            .fixedSize()

            TextField("Muster", text: $pattern, prompt: Text(ActivityRuleEditor.prompt(rule.kind)))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .focused($isEditing)
                .onSubmit(commit)

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Picker("Projekt", selection: Binding(
                get: { rule.projectId },
                set: { projectId in
                    var updated = rule
                    updated.projectId = projectId
                    store.saveActivityRule(updated)
                }
            )) {
                ForEach(projectOptions) { project in
                    Text(project.isArchived ? "\(project.name) (archiviert)" : project.name).tag(project.id)
                }
            }
            .labelsHidden()
            .frame(width: 120)

            Button(role: .destructive) {
                store.deleteActivityRule(rule)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Regel löschen")
        }
        .onAppear { pattern = rule.pattern }
        .onChange(of: rule.pattern) { if !isEditing { pattern = rule.pattern } }
        .onChange(of: isEditing) { if !isEditing { commit() } }
    }

    /// Aktive Projekte, dazu das Projekt der Regel, falls es archiviert ist.
    private var projectOptions: [Project] {
        var options = store.projects
        if !options.contains(where: { $0.id == rule.projectId }), let own = store.projectsById[rule.projectId] {
            options.append(own)
        }
        return options
    }

    /// Geändertes Muster speichern; leer → altes Muster zurück.
    private func commit() {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            pattern = rule.pattern
            return
        }
        guard trimmed != rule.pattern else { return }
        var updated = rule
        updated.pattern = trimmed
        store.saveActivityRule(updated)
    }
}

// MARK: - Regel anlegen

/// Popover zum Anlegen einer Regel: Art, Muster (mit Hilfen je Art) und Projekt.
struct ActivityRuleEditor: View {
    @Environment(TaktStore.self) private var store

    let title: String
    @State var kind: ActivityRuleKind
    @State var pattern: String
    @State var projectId: UUID?
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            Form {
                Picker("Art", selection: $kind) {
                    ForEach(ActivityRuleKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                LabeledContent("Muster") {
                    HStack(spacing: 6) {
                        TextField("Muster", text: $pattern, prompt: Text(Self.prompt(kind)))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                        helperButton
                    }
                }
                Picker("Projekt", selection: $projectId) {
                    ForEach(store.projects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
            }
            .formStyle(.columns)

            Text(Self.hint(kind))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel, action: onDone)
                    .keyboardShortcut(.cancelAction)
                Button("Anlegen", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    @ViewBuilder
    private var helperButton: some View {
        switch kind {
        case .bundleID:
            Menu {
                ForEach(Self.runningApps, id: \.bundleID) { app in
                    Button(app.name) { pattern = app.bundleID }
                }
            } label: {
                Image(systemName: "app.badge")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Laufende App wählen")
        case .repoPath:
            Button {
                chooseFolder()
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Ordner wählen …")
        case .windowTitleContains:
            EmptyView()
        }
    }

    private var canSave: Bool {
        projectId != nil && !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard let projectId, canSave else { return }
        if store.addActivityRule(kind: kind, pattern: pattern, projectId: projectId) {
            onDone()
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Wählen"
        let devFolder = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("dev")
        if FileManager.default.fileExists(atPath: devFolder.path) { panel.directoryURL = devFolder }
        if panel.runModal() == .OK, let url = panel.url {
            pattern = ActivityHeuristics.abbreviate(url.path)
        }
    }

    /// Normale Apps, die gerade laufen (ohne Takt), nach Name.
    private static var runningApps: [(name: String, bundleID: String)] {
        let own = Bundle.main.bundleIdentifier
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> (name: String, bundleID: String)? in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, id != own else { return nil }
            return (app.localizedName ?? id, id)
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func shortTitle(_ kind: ActivityRuleKind) -> String {
        switch kind {
        case .bundleID: "App"
        case .windowTitleContains: "Fenstertitel enthält"
        case .repoPath: "Repo-Pfad"
        }
    }

    static func prompt(_ kind: ActivityRuleKind) -> String {
        switch kind {
        case .bundleID: "com.apple.dt.Xcode"
        case .windowTitleContains: "Kundenportal"
        case .repoPath: "~/dev/eventbuster-app"
        }
    }

    static func hint(_ kind: ActivityRuleKind) -> String {
        switch kind {
        case .bundleID:
            "Bundle-ID der App. Passt immer, wenn diese App vorne ist – auch ohne Bedienungshilfen-Freigabe."
        case .windowTitleContains:
            "Teil des Fenstertitels, ohne Rücksicht auf Groß-/Kleinschreibung – z. B. für Browser-Tabs oder Dokumente."
        case .repoPath:
            "Git-Repository in diesem Ordner oder darunter (~/dev/takt passt zu ~/dev/takt/TaktCore, nicht zu ~/dev/takt2)."
        }
    }
}
