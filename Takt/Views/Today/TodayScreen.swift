import SwiftUI

// Ansicht „Heute“ im Entwurf „Farbkarte“. Von oben nach unten:
//   Start-Kapseln: alle aktiven Projekte, gruppiert nach Business | Privat, dazu „+ Eintrag“.
//   Schnelleingabe: Feld mit Live-Vorschau (⌘N), siehe `TodayQuickEntry`.
//   Farbkarte: läuft → Projektfarbe füllt die Karte (wie Widget „Farbfläche“);
//              Pause → neutrale Karte mit Tagessumme und „Weiter mit …“.
//   Nächster Block: geplanter Start („14:00 · Kundenportal“) oder „Block planen…“.
//   Hinweis: Termin läuft, Timer auf anderem Projekt („Wechseln zu …“), siehe `TodayEvents`.
//   Tagesleiste: Zeitfenster mit farbigen Segmenten und Jetzt-Marke, Fokus-Kennzahlen darüber;
//                Kalendertermine als schraffierte schmale Spur oberhalb.
//   Termine heute: kompakte Liste mit „Als Eintrag“ (nur mit Kalender-Anbindung).
//   Einträge: schlichte Liste, neueste oben.
// Rein darstellend: Daten kommen als `TodayData`, Aktionen als `TodayActions`.

struct TodayScreen: View {
    let data: TodayData
    var actions = TodayActions()
    /// Nur für Vorschauen und das Render-Harness: vorbelegter Text der Schnelleingabe.
    var initialQuickText = ""
    @Environment(\.colorScheme) private var scheme
    /// Ausgeblendete Hinweise „Termin läuft“ (je Termin).
    @State private var dismissedHints: Set<String> = []
    private var theme: DesignTheme { DesignTheme(scheme: scheme) }

    var body: some View {
        Group {
            if data.projects.isEmpty && data.entries.isEmpty {
                TodayFirstRun(theme: theme, actions: actions)
            } else {
                content
            }
        }
        .padding(.horizontal, Self.sideInset)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                TodayStartRow(data: data, theme: theme, actions: actions)
                if !data.projects.isEmpty {
                    TodayQuickEntry(theme: theme, actions: actions, initialText: initialQuickText)
                    TipRow(tip: .today)
                }
            }
            if let running = data.running {
                TodayRunningCard(data: data, running: running, theme: theme, actions: actions)
            } else {
                TodayIdleCard(data: data, theme: theme, actions: actions)
            }
            TodayNextBlockRow(data: data, theme: theme, actions: actions)
                .padding(.top, -8)
            if let hint = data.meetingHint, !dismissedHints.contains(hint.event.id) {
                TodayMeetingHintRow(hint: hint, theme: theme, actions: actions) {
                    dismissedHints.insert(hint.event.id)
                }
                .padding(.top, -10)
            }
            VStack(alignment: .leading, spacing: 10) {
                TodayDayStrip(data: data, theme: theme)
                if !data.events.isEmpty || !data.allDayEvents.isEmpty {
                    TodayEventList(data: data, theme: theme, actions: actions)
                }
            }
            TodayEntryList(data: data, theme: theme, actions: actions)
        }
    }

    /// Seitlicher Rand des Inhalts.
    static let sideInset: CGFloat = 28
}

// MARK: - Erster Start

/// Leerer Zustand ohne Projekte und Einträge: erklärt in drei Schritten, wie Takt funktioniert,
/// und legt mit einem Klick das erste Projekt an.
private struct TodayFirstRun: View {
    let theme: DesignTheme
    let actions: TodayActions

    var body: some View {
        EmptyStateView(
            symbol: "folder.badge.plus",
            title: "Noch keine Projekte",
            message: "Ein Projekt ist das, worauf du Zeit buchst – ein Kunde, ein Produkt oder etwas Privates wie „Garten“.",
            steps: [
                "Projekt anlegen: Name, Farbe, Business oder Privat.",
                "Oben auf die Projekt-Kapsel klicken – der Timer läuft.",
                "„Stoppen“ (⌘.) beendet ihn. Vergessenes trägst du mit ⌘N nach, z. B. „Kundenportal 9-10:30“.",
            ],
            actionTitle: "Projekt anlegen",
            action: actions.createProject,
            helpTopic: "start"
        )
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(theme.hairline, lineWidth: 1))
        .padding(.top, 8)
    }
}

// MARK: - Start-Kapseln

private struct TodayStartRow: View {
    let data: TodayData
    let theme: DesignTheme
    let actions: TodayActions

    private var business: [TodayData.ProjectItem] { data.projects.filter(\.isBusiness) }
    private var personal: [TodayData.ProjectItem] { data.projects.filter { !$0.isBusiness } }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if data.projects.isEmpty {
                // Nur archivierte Projekte: Einträge sind da, aber nichts zum Starten.
                HStack(spacing: 10) {
                    Text("Kein aktives Projekt zum Starten.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    OutlinePillButton(title: "Projekt anlegen", theme: theme, action: actions.createProject)
                        .help("Neues Projekt anlegen – danach erscheint es hier als Start-Kapsel")
                }
                .frame(height: 28)
            } else {
                // Bricht bei vielen Projekten in die nächste Zeile um.
                FlowLayout(spacing: 6, lineSpacing: 8) {
                    if !business.isEmpty {
                        groupLabel("Business")
                        ForEach(business) { pill($0) }
                    }
                    if !business.isEmpty && !personal.isEmpty {
                        Rectangle()
                            .fill(theme.hairline)
                            .frame(width: 1, height: 18)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                    }
                    if !personal.isEmpty {
                        groupLabel("Privat")
                        ForEach(personal) { pill($0) }
                    }
                }
            }
            Spacer(minLength: 0)
            OutlinePillButton(title: "Eintrag", theme: theme, action: actions.addEntry)
                .help("Eintrag nachtragen: Projekt und Zeitraum von Hand eingeben (schneller: ⌘N)")
                .disabled(data.projects.isEmpty)
        }
    }

    private func groupLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.tertiary)
            .padding(.trailing, 4)
            .frame(height: 28)
            .help("\(title)-Projekte – klick auf eine Kapsel startet den Timer. Die Art legst du im Projekt fest.")
    }

    private func pill(_ project: TodayData.ProjectItem) -> some View {
        let isRunning = data.running?.project.id == project.id
        return TodayStartPill(project: project, isRunning: isRunning, theme: theme) {
            if !isRunning { actions.start(project) }
        }
    }
}

private struct TodayStartPill: View {
    let project: TodayData.ProjectItem
    let isRunning: Bool
    let theme: DesignTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle().fill(project.color).frame(width: 8, height: 8)
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if isRunning {
                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(project.color)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(project.color)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 11)
            .frame(height: 28)
            .background(theme.tint(project.color, strong: isRunning), in: Capsule())
            .overlay(Capsule().stroke(isRunning ? project.color.opacity(0.55) : .clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isRunning
              ? "\(project.name) läuft – stoppen mit „Stoppen“ (⌘.)"
              : "\(project.name) starten – ein laufender Timer wird dabei gestoppt")
        .accessibilityLabel(isRunning ? "\(project.name) läuft" : "\(project.name) starten")
    }
}

// MARK: - Farbkarte

private struct TodayRunningCard: View {
    let data: TodayData
    let running: TodayData.EntryItem
    let theme: DesignTheme
    let actions: TodayActions

    @State private var isStopPopoverShown = false
    @State private var nextStep = ""
    @State private var tag = ""

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(running.project.name)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(["seit \(TodayFormat.clock(running.start))", running.project.kind, running.tag.map { "#\($0)" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 2)
                    .help("Beginn · Art des Projekts · Tag des Eintrags")
                Spacer(minLength: 0)
                Text(TodayFormat.duration(running.duration(now: data.now)))
                    .font(.system(size: 92, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.bottom, -14)
                    .help("Laufzeit dieses Eintrags in Stunden:Minuten")
            }
            .layoutPriority(1)
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 10) {
                if let step = data.runningNextStep {
                    // Beim Start gezeigt: was beim letzten Stopp als Nächstes notiert wurde.
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Nächster Schritt")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .help(TermHelp.nextStep)
                        Text(step)
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(3)
                            .frame(maxWidth: 260, alignment: .trailing)
                    }
                }
                Spacer(minLength: 0)
                stopButton
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 20)
        .padding(.bottom, 22)
        .frame(height: 190)
        .background(theme.colorField(running.project.colorBehindWhite))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var stopButton: some View {
        Button {
            nextStep = ""
            tag = running.tag ?? ""
            isStopPopoverShown = true
        } label: {
            HStack(spacing: 8) {
                StopGlyph(color: running.project.colorBehindWhite, size: 11)
                Text("Stoppen")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(running.project.colorBehindWhite.mix(with: .black, by: 0.2))
            }
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(.white, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(".", modifiers: .command)
        .help("Timer stoppen (⌘.)")
        .popover(isPresented: $isStopPopoverShown, arrowEdge: .bottom) {
            stopPopover
        }
    }

    private var stopPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Nächster Schritt (optional)", text: $nextStep)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                    .onSubmit(stop)
                Text("Erscheint beim nächsten Start von \(running.project.name) – damit du weißt, wo du weitermachst.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 280, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                TextField("Tag (optional, z. B. Meeting)", text: $tag)
                    .help("Ein Stichwort zum Eintrag; Berichte schlüsseln die Zeit danach auf")
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                    .onSubmit(stop)
                TagSuggestionChips(text: $tag, suggestions: actions.tagSuggestions(running.project.id, tag))
                    .frame(width: 280, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) {
                    isStopPopoverShown = false
                }
                .keyboardShortcut(.cancelAction)
                Button("Stoppen", action: stop)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    private func stop() {
        isStopPopoverShown = false
        actions.stop(nextStep, tag)
    }
}

private struct TodayIdleCard: View {
    let data: TodayData
    let theme: DesignTheme
    let actions: TodayActions

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Nichts läuft")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let pause = data.pauseSinceLastStop {
                    Text("Pause seit \(TodayFormat.clock(pause.since)) · \(TodayFormat.duration(pause.duration))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.tertiary)
                        .padding(.top, 2)
                        .help("Zeit seit dem letzten Stopp heute")
                }
                Spacer(minLength: 0)
                Text("Heute erfasst")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.tertiary)
                    .help("Summe aller heutigen Einträge in Stunden:Minuten")
                Text(TodayFormat.duration(data.todayTotal))
                    .font(.system(size: 76, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.bottom, -12)
            }
            .layoutPriority(1)
            Spacer(minLength: 16)
            if let resume = data.resume {
                VStack(alignment: .trailing, spacing: 10) {
                    if let step = resume.nextStep {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Nächster Schritt")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(theme.tertiary)
                                .help(TermHelp.nextStep)
                            Text(step)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(3)
                                .frame(maxWidth: 260, alignment: .trailing)
                        }
                    }
                    Button { actions.start(resume.project) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Weiter mit \(resume.project.name)")
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 40)
                        .background(resume.project.colorBehindWhite, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Weiter mit: startet \(resume.project.name) erneut – das zuletzt genutzte Projekt")
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 20)
        .padding(.bottom, 22)
        .frame(height: 190)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(theme.hairline, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            dayOffLink
                .padding(.top, 16)
                .padding(.trailing, 20)
        }
    }

    /// „Heute frei …“ bzw. die Art des freien Tags; öffnet „Freie Tage“ für heute.
    private var dayOffLink: some View {
        Button(action: actions.markTodayOff) {
            HStack(spacing: 5) {
                Image(systemName: data.todayOff == nil ? "sun.max" : "sun.max.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(data.todayOff.map { "Heute frei: \($0)" } ?? "Heute frei …")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(data.todayOff == nil ? AnyShapeStyle(theme.tertiary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(data.todayOff == nil ? Color.clear : theme.track, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(data.todayOff == nil ? "Heute als freien Tag markieren (Urlaub, Krank …)" : "Freien Tag ändern")
    }
}

// MARK: - Nächster Block

private struct TodayNextBlockRow: View {
    let data: TodayData
    let theme: DesignTheme
    let actions: TodayActions

    @State private var isPlanning = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Nächster Block")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.tertiary)
                .help(TermHelp.planBlock)
            if let block = data.plannedBlock {
                planned(block)
            } else {
                Button { isPlanning = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Block planen …")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .overlay(Capsule().stroke(theme.hairline, lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(data.projects.isEmpty)
                .help(TermHelp.planBlock)
                .popover(isPresented: $isPlanning, arrowEdge: .bottom) { popover }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 28)
    }

    private func planned(_ block: TodayData.PlannedItem) -> some View {
        let isDue = block.isDue(now: data.now)
        let isRunning = data.running?.project.id == block.project.id
        return HStack(alignment: .center, spacing: 10) {
            // Klick auf den Block: ändern.
            Button { isPlanning = true } label: {
                HStack(spacing: 7) {
                    Circle().fill(block.project.color).frame(width: 8, height: 8)
                    Text("\(TodayFormat.plannedTime(block.startAt, now: data.now)) · \(block.project.name)")
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if isDue {
                        Text("fällig")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(block.project.color)
                    }
                    if let note = block.note {
                        Text(note)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isDue ? "Fällig: der geplante Beginn ist erreicht. Klicken zum Ändern." : "Geplanten Block ändern")
            .popover(isPresented: $isPlanning, arrowEdge: .bottom) { popover }

            if !isRunning {
                Button(action: actions.startPlannedBlock) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(block.project.color)
                        Text("Jetzt starten")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(theme.tint(block.project.color, strong: isDue), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("\(block.project.name) jetzt starten")
            }

            Button(action: actions.clearPlannedBlock) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.tertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Geplanten Block entfernen")
            .accessibilityLabel("Geplanten Block entfernen")
        }
    }

    private var popover: some View {
        TodayPlanBlockPopover(data: data) { projectId, startAt, note in
            isPlanning = false
            actions.planBlock(projectId, startAt, note)
        } cancel: {
            isPlanning = false
        }
    }
}

/// Popover „Block planen“: Projekt, Uhrzeit (Standard: nächste volle Viertelstunde), Notiz.
private struct TodayPlanBlockPopover: View {
    let data: TodayData
    let save: (UUID, Date, String) -> Void
    let cancel: () -> Void

    @State private var projectId: UUID
    @State private var time: Date
    @State private var note: String

    init(data: TodayData, save: @escaping (UUID, Date, String) -> Void, cancel: @escaping () -> Void) {
        self.data = data
        self.save = save
        self.cancel = cancel
        // Vorbelegung: vorhandener Block, sonst „Weiter mit …“, sonst ein nicht laufendes Projekt.
        let fallback = data.projects.first { $0.id != data.running?.project.id } ?? data.projects.first
        let project = data.plannedBlock?.project ?? data.resume?.project ?? fallback
        _projectId = State(initialValue: project?.id ?? UUID())
        _time = State(initialValue: data.plannedBlock?.startAt ?? Self.nextQuarterHour(after: data.now))
        _note = State(initialValue: data.plannedBlock?.note ?? "")
    }

    /// Gewählte Uhrzeit am heutigen Tag; liegt sie (mehr als 5 Minuten) zurück, morgen.
    private var startAt: Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        let today = calendar.date(
            bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: data.now
        ) ?? time
        if today < data.now.addingTimeInterval(-5 * 60) {
            return calendar.date(byAdding: .day, value: 1, to: today) ?? today
        }
        return today
    }

    private var isTomorrow: Bool { !Calendar.current.isDate(startAt, inSameDayAs: data.now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(data.plannedBlock == nil ? "Block planen" : "Block ändern")
                    .font(.system(size: 13, weight: .semibold))
                Text("Wenn es so weit ist, dann geht es damit weiter: Takt erinnert zum Beginn, ein Klick startet den Timer.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Projekt").foregroundStyle(.secondary)
                    Picker("Projekt", selection: $projectId) {
                        ForEach(data.projects) { project in
                            Text(project.name).tag(project.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                GridRow {
                    Text("Uhrzeit").foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        DatePicker("Uhrzeit", selection: $time, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        if isTomorrow {
                            Text("morgen")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                GridRow {
                    Text("Notiz").foregroundStyle(.secondary)
                    TextField("Notiz", text: $note, prompt: Text("optional"))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(submit)
                }
            }
            .font(.system(size: 13))
            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Planen", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!data.projects.contains { $0.id == projectId })
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func submit() {
        guard data.projects.contains(where: { $0.id == projectId }) else { return }
        save(projectId, startAt, note)
    }

    /// Nächste volle Viertelstunde nach `date` (genau auf der Viertelstunde: die folgende).
    static func nextQuarterHour(after date: Date) -> Date {
        let quarter: TimeInterval = 15 * 60
        let next = (date.timeIntervalSinceReferenceDate / quarter).rounded(.down) * quarter + quarter
        return Date(timeIntervalSinceReferenceDate: next)
    }
}

// MARK: - Tagesleiste

private struct TodayDayStrip: View {
    let data: TodayData
    let theme: DesignTheme

    var body: some View {
        let window = data.dayWindow
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // Läuft: Tagessumme hier. Pause: steht groß in der Karte, hier nur der Titel.
                Text(data.running == nil ? "Tagesverlauf" : "Heute")
                    .font(.system(size: 13, weight: .semibold))
                    .help("Farbige Abschnitte sind deine Einträge, der senkrechte Strich ist jetzt.")
                if data.running != nil {
                    Text(TodayFormat.duration(data.todayTotal))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                // Fokus-Kennzahlen – bewusst leise.
                if !data.entries.isEmpty {
                    HStack(spacing: 8) {
                        Text("\(data.switches) Wechsel")
                            .help(TermHelp.switches)
                        Text("·")
                        Text("längster Block \(TodayFormat.duration(data.longestBlock))")
                            .help(TermHelp.longestBlock)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.tertiary)
                    .monospacedDigit()
                }
            }
            GeometryReader { geo in
                let width = geo.size.width
                // Mit Terminen: schmale Terminspur (6 pt) über den Eintragssegmenten.
                let hasEvents = !data.events.isEmpty
                let laneHeight = Self.laneHeight(hasEvents: hasEvents)
                let entryTop: CGFloat = hasEvents ? Self.eventLane + Self.eventGap + 5 : 5
                ZStack(alignment: .topLeading) {
                    // Stundenraster
                    ForEach(Array(window), id: \.self) { hour in
                        Rectangle()
                            .fill(theme.hairline)
                            .frame(width: 1, height: laneHeight - 4)
                            .offset(x: x(Double(hour), width, window), y: 2)
                    }
                    if hasEvents {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(theme.track)
                            .frame(width: width, height: Self.eventLane)
                            .offset(y: 5)
                        ForEach(data.events) { event in
                            let start = x(data.hourOfDay(event.start), width, window)
                            let end = x(data.hourOfDay(event.end), width, window)
                            TodayEventSegment(color: event.calendarColor, dark: theme.dark)
                                .frame(width: max(3, end - start - 1.5), height: Self.eventLane)
                                .offset(x: start, y: 5)
                                .help("\(event.title) · \(TodayFormat.clock(event.start))–\(TodayFormat.clock(event.end))")
                        }
                    }
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(theme.track)
                        .frame(width: width, height: 16)
                        .offset(y: entryTop)
                    ForEach(data.entries) { entry in
                        let start = x(data.hourOfDay(entry.start), width, window)
                        let end = x(data.hourOfDay(entry.end ?? data.now), width, window)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(entry.project.color.opacity(entry.isRunning ? 0.85 : 1))
                            .frame(width: max(3, end - start - 1.5), height: 16)
                            .offset(x: start, y: entryTop)
                    }
                    // Jetzt-Marke (nur innerhalb des sichtbaren Fensters)
                    let nowHour = data.hourOfDay(data.now)
                    if nowHour >= Double(window.lowerBound), nowHour <= Double(window.upperBound) {
                        Capsule()
                            .fill(.primary)
                            .frame(width: 2, height: laneHeight)
                            .offset(x: x(nowHour, width, window) - 1)
                    }
                }
                .frame(width: width, height: laneHeight, alignment: .topLeading)
            }
            .frame(height: Self.laneHeight(hasEvents: !data.events.isEmpty))
            .accessibilityElement()
            .accessibilityLabel("Tagesverlauf")
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    ForEach(Array(stride(from: window.lowerBound, through: window.upperBound, by: 2)), id: \.self) { hour in
                        Text(String(format: "%02d", hour))
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(theme.tertiary)
                            .fixedSize()
                            .frame(width: 30)
                            .offset(x: x(Double(hour), geo.size.width, window) - 15)
                    }
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)
        }
    }

    /// Höhe der Terminspur und Abstand zu den Einträgen.
    static let eventLane: CGFloat = 6
    static let eventGap: CGFloat = 4

    /// Gesamthöhe der Leiste: 26 pt, mit Terminspur entsprechend mehr.
    static func laneHeight(hasEvents: Bool) -> CGFloat {
        hasEvents ? 26 + eventLane + eventGap : 26
    }

    private func x(_ hour: Double, _ width: CGFloat, _ window: ClosedRange<Int>) -> CGFloat {
        let lower = Double(window.lowerBound)
        let upper = Double(window.upperBound)
        return CGFloat((min(max(hour, lower), upper) - lower) / (upper - lower)) * width
    }
}

// MARK: - Einträge

private struct TodayEntryList: View {
    let data: TodayData
    let theme: DesignTheme
    let actions: TodayActions

    @State private var scrollWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0

    var body: some View {
        if data.entries.isEmpty {
            VStack(spacing: 4) {
                Text("Heute noch keine Einträge")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Starte einen Timer über eine Kapsel oben oder tippe ⌘N: „Kundenportal 9-10:30“.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 12)
        } else {
            // Passt die Liste, ohne Rollen; sonst rollt sie mit der Rollleiste am Fensterrand.
            ViewThatFits(in: .vertical) {
                rows
                ScrollView {
                    rows
                        .padding(.leading, TodayScreen.sideInset)
                        // Eine dauerhaft sichtbare Rollleiste nimmt Breite weg – ausgleichen,
                        // damit die Dauer-Spalte bündig mit der Karte bleibt.
                        .padding(.trailing, max(0, TodayScreen.sideInset - scrollerWidth))
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { contentWidth = $0 }
                }
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { scrollWidth = $0 }
                .padding(.horizontal, -TodayScreen.sideInset)
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(data.entries.reversed().enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Rectangle().fill(theme.hairline).frame(height: 1).padding(.leading, 17)
                }
                Button { actions.openEntry(entry) } label: { row(entry) }
                    .buttonStyle(.plain)
                    .help("Klicken zum Bearbeiten · Rechtsklick zum Löschen")
                    .contextMenu {
                        Button("Bearbeiten …") { actions.openEntry(entry) }
                        Divider()
                        Button("Löschen …", role: .destructive) { actions.deleteEntry(entry) }
                    }
            }
        }
        .padding(.bottom, 16)
    }

    /// Breite, die eine dauerhaft sichtbare Rollleiste dem Inhalt wegnimmt (sonst 0).
    private var scrollerWidth: CGFloat {
        guard scrollWidth > 0, contentWidth > 0 else { return 0 }
        return min(TodayScreen.sideInset, max(0, scrollWidth - contentWidth))
    }

    private func row(_ entry: TodayData.EntryItem) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Capsule()
                .fill(entry.project.color)
                .frame(width: 3, height: entry.nextStep == nil ? 18 : 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(entry.project.name)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    if let tag = entry.tag {
                        TagCapsule(tag: tag)
                    }
                    if entry.isRunning {
                        Text("läuft")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(entry.project.color)
                    }
                }
                if let step = entry.nextStep {
                    Text(step)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            Text(TodayFormat.range(entry))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(TodayFormat.duration(entry.duration(now: data.now)))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, entry.nextStep == nil ? 10 : 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Zum Bearbeiten öffnen")
    }
}

#if DEBUG
#Preview("Läuft") {
    TodayScreen(data: .sampleRunning)
        .frame(width: 920, height: 548)
}

#Preview("Pause") {
    TodayScreen(data: .sampleIdle)
        .frame(width: 920, height: 548)
}

#Preview("Mit Terminen") {
    TodayScreen(data: .sampleWithEvents)
        .frame(width: 920, height: 640)
}
#endif
