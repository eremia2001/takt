import SwiftUI
#if canImport(TaktCore)
import TaktCore
#endif

// Inhalt des Menüleisten-Fensters, rein darstellend (Daten als `MenuBarPanelData`, Aktionen als
// `MenuBarPanelActions`), damit es auch außerhalb der App gezeichnet werden kann.
// Von oben nach unten: Karte wie das mittlere Widget (läuft: Farbfläche; Pause: neutrale Karte
// mit Tagessumme), Projektliste zum Starten, Fußzeile „Takt öffnen · Einstellungen… · Beenden“.

struct MenuBarPanelData {
    struct ProjectItem: Identifiable, Equatable {
        let id: UUID
        let name: String
        let colorHex: String
        let isBusiness: Bool
        /// Heute erfasst inklusive laufendem Eintrag.
        let todayTotal: TimeInterval

        var color: Color { Color(hex: colorHex) }
        /// Projektfarbe als Grund für weiße Schrift.
        var colorBehindWhite: Color { DesignColor.behindWhite(colorHex) }
    }

    struct RunningItem: Equatable {
        let project: ProjectItem
        let start: Date
    }

    var running: RunningItem?
    var projects: [ProjectItem]
    /// Tagessumme inklusive laufendem Eintrag.
    var todayTotal: TimeInterval
    var now: Date
}

struct MenuBarPanelActions {
    var start: (UUID) -> Void = { _ in }
    var stop: () -> Void = {}
    var openApp: () -> Void = {}
    var openSettings: () -> Void = {}
    var quit: () -> Void = {}
}

struct MenuBarPanel: View {
    let data: MenuBarPanelData
    var actions = MenuBarPanelActions()

    @Environment(\.colorScheme) private var scheme
    private var theme: DesignTheme { DesignTheme(scheme: scheme) }

    static let width: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let running = data.running {
                    MenuBarRunningCard(running: running, data: data, theme: theme, stop: actions.stop)
                } else {
                    MenuBarIdleCard(data: data, theme: theme)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            MenuBarProjectList(data: data, theme: theme, start: actions.start)
                .padding(.top, 10)

            Rectangle()
                .fill(theme.hairline)
                .frame(height: 1)
                .padding(.horizontal, 10)

            HStack(spacing: 2) {
                MenuBarFooterButton(title: "Takt öffnen", theme: theme, action: actions.openApp)
                MenuBarFooterButton(title: "Einstellungen…", theme: theme, action: actions.openSettings)
                Spacer(minLength: 0)
                MenuBarFooterButton(title: "Beenden", theme: theme, action: actions.quit)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .frame(width: Self.width)
        .background(theme.window)
    }
}

// MARK: - Karte

private struct MenuBarRunningCard: View {
    let running: MenuBarPanelData.RunningItem
    let data: MenuBarPanelData
    let theme: DesignTheme
    let stop: () -> Void

    var body: some View {
        let project = running.project
        VStack(alignment: .leading, spacing: 0) {
            Text(project.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text("seit \(ClockFormat.time(running.start)) · heute \(DurationFormat.hourMinute(data.todayTotal))")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.75))
                .padding(.top, 1)
            Spacer(minLength: 8)
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(DurationFormat.hourMinute(data.now.timeIntervalSince(running.start)))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.bottom, -7)
                Spacer(minLength: 0)
                Button(action: stop) {
                    HStack(spacing: 7) {
                        StopGlyph(color: project.colorBehindWhite, size: 9)
                        Text("Stoppen")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(project.colorBehindWhite.mix(with: .black, by: 0.2))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(.white, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Timer stoppen")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 14)
        .frame(height: 118)
        .background(theme.colorField(project.colorBehindWhite))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct MenuBarIdleCard: View {
    let data: MenuBarPanelData
    let theme: DesignTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nichts läuft")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text("Heute erfasst")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.tertiary)
            Text(DurationFormat.hourMinute(data.todayTotal))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.bottom, -7)
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 118)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.hairline, lineWidth: 1))
    }
}

// MARK: - Projekte

private struct MenuBarProjectList: View {
    let data: MenuBarPanelData
    let theme: DesignTheme
    let start: (UUID) -> Void

    /// Ab dieser Zahl scrollt die Liste, damit das Fenster nicht über den Bildschirm wächst.
    private static let maxVisibleRows = 9
    private static let rowHeight: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Projekte")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.tertiary)
                .padding(.horizontal, 16)
                .padding(.bottom, 2)

            if data.projects.isEmpty {
                Text("Lege in Takt unter „Projekte“ ein erstes Projekt an.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            } else if data.projects.count > Self.maxVisibleRows {
                ScrollView {
                    rows
                }
                .scrollIndicators(.automatic)
                .frame(height: CGFloat(Self.maxVisibleRows) * (Self.rowHeight + 2))
            } else {
                rows
            }
        }
        .padding(.bottom, 8)
    }

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(data.projects) { project in
                MenuBarProjectRow(
                    project: project,
                    isRunning: data.running?.project.id == project.id,
                    theme: theme,
                    height: Self.rowHeight
                ) {
                    start(project.id)
                }
            }
        }
        .padding(.horizontal, 6)
    }
}

private struct MenuBarProjectRow: View {
    let project: MenuBarPanelData.ProjectItem
    let isRunning: Bool
    let theme: DesignTheme
    let height: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            // Das laufende Projekt erneut „starten“ wäre ein No-op; kein `.disabled`, damit die Zeile nicht ausgegraut wird.
            if !isRunning { action() }
        } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(project.color)
                    .frame(width: 8, height: 8)
                Text(project.name)
                    .font(.system(size: 13, weight: isRunning ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if project.todayTotal >= 60 {
                    Text(DurationFormat.hourMinute(project.todayTotal))
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(theme.tertiary)
                }
                trailingSymbol
                    .frame(width: 14)
            }
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(isRunning ? "\(project.name) läuft" : "\(project.name) starten")
        .accessibilityLabel(isRunning ? "\(project.name) läuft" : "\(project.name) starten")
    }

    @ViewBuilder
    private var trailingSymbol: some View {
        if isRunning {
            Image(systemName: "waveform")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(project.color)
        } else {
            Image(systemName: "play.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(project.color)
                .opacity(isHovered ? 1 : 0)
        }
    }

    private var background: Color {
        if isRunning { return theme.tint(project.color, strong: true) }
        return isHovered ? theme.track : .clear
    }
}

// MARK: - Fußzeile

private struct MenuBarFooterButton: View {
    let title: String
    let theme: DesignTheme
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(isHovered ? theme.track : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
