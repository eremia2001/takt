import SwiftUI

// Ansicht „Heute“ im Entwurf „Farbkarte“. Von oben nach unten:
//   Start-Kapseln: alle aktiven Projekte, gruppiert nach Business | Privat, dazu „+ Eintrag“.
//   Farbkarte: läuft → Projektfarbe füllt die Karte (wie Widget „Farbfläche“);
//              Pause → neutrale Karte mit Tagessumme und „Weiter mit …“.
//   Tagesleiste: Zeitfenster mit farbigen Segmenten und Jetzt-Marke, Fokus-Kennzahlen darüber.
//   Einträge: schlichte Liste, neueste oben.
// Rein darstellend: Daten kommen als `TodayData`, Aktionen als `TodayActions`.

struct TodayScreen: View {
    let data: TodayData
    var actions = TodayActions()
    @Environment(\.colorScheme) private var scheme
    private var theme: DesignTheme { DesignTheme(scheme: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TodayStartRow(data: data, theme: theme, actions: actions)
            if let running = data.running {
                TodayRunningCard(data: data, running: running, theme: theme, actions: actions)
            } else {
                TodayIdleCard(data: data, theme: theme, actions: actions)
            }
            TodayDayStrip(data: data, theme: theme)
            TodayEntryList(data: data, theme: theme, actions: actions)
        }
        .padding(.horizontal, Self.sideInset)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Seitlicher Rand des Inhalts.
    static let sideInset: CGFloat = 28
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
                Button(action: actions.showProjects) {
                    Text("Lege unter „Projekte“ ein erstes Projekt an.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(height: 28)
                }
                .buttonStyle(.plain)
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
                .help("Eintrag manuell hinzufügen")
                .disabled(data.projects.isEmpty)
        }
    }

    private func groupLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.tertiary)
            .padding(.trailing, 4)
            .frame(height: 28)
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
        .help(isRunning ? "\(project.name) läuft" : "\(project.name) starten")
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

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(running.project.name)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("seit \(TodayFormat.clock(running.start)) · \(running.project.kind)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 2)
                Spacer(minLength: 0)
                Text(TodayFormat.duration(running.duration(now: data.now)))
                    .font(.system(size: 92, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.bottom, -14)
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
            TextField("Nächster Schritt (optional)", text: $nextStep)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit(stop)
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
        actions.stop(nextStep)
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
                }
                Spacer(minLength: 0)
                Text("Heute erfasst")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.tertiary)
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
                    .help("\(resume.project.name) starten")
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 20)
        .padding(.bottom, 22)
        .frame(height: 190)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(theme.hairline, lineWidth: 1))
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
                        Text("·")
                        Text("längster Block \(TodayFormat.duration(data.longestBlock))")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.tertiary)
                    .monospacedDigit()
                }
            }
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    // Stundenraster
                    ForEach(Array(window), id: \.self) { hour in
                        Rectangle()
                            .fill(theme.hairline)
                            .frame(width: 1, height: 22)
                            .offset(x: x(Double(hour), width, window))
                    }
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(theme.track)
                        .frame(height: 16)
                    ForEach(data.entries) { entry in
                        let start = x(data.hourOfDay(entry.start), width, window)
                        let end = x(data.hourOfDay(entry.end ?? data.now), width, window)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(entry.project.color.opacity(entry.isRunning ? 0.85 : 1))
                            .frame(width: max(3, end - start - 1.5), height: 16)
                            .offset(x: start)
                    }
                    // Jetzt-Marke (nur innerhalb des sichtbaren Fensters)
                    let nowHour = data.hourOfDay(data.now)
                    if nowHour >= Double(window.lowerBound), nowHour <= Double(window.upperBound) {
                        Capsule()
                            .fill(.primary)
                            .frame(width: 2, height: 26)
                            .offset(x: x(nowHour, width, window) - 1)
                    }
                }
                .frame(height: 26)
            }
            .frame(height: 26)
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
            Text("Heute noch keine Einträge")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
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
#endif
