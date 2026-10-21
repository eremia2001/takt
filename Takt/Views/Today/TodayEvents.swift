import SwiftUI

// Kalendertermine in „Heute“: schraffierte Segmente der Terminspur (Tagesleiste), die kompakte
// Liste „Termine heute“ mit „Als Eintrag“ und der Hinweis, wenn ein Termin läuft, der Timer aber
// auf einem anderen Projekt steht. Rein darstellend wie `TodayScreen`.

// MARK: - Segment der Terminspur

/// Termin in der Tagesleiste: Kalenderfarbe mit 50 % Deckung, leicht schraffiert.
struct TodayEventSegment: View {
    let color: Color
    let dark: Bool

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let shape = Path(roundedRect: rect, cornerRadius: 2, style: .continuous)
            context.clip(to: shape)
            context.fill(shape, with: .color(color.opacity(0.5)))
            // Schraffur: feine Diagonalen im Abstand von 4 pt.
            var stripes = Path()
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                stripes.move(to: CGPoint(x: x, y: size.height))
                stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 4
            }
            context.stroke(stripes, with: .color(.white.opacity(dark ? 0.22 : 0.45)), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Hinweis „Termin läuft“

/// „Termin ‚Review Gerlach‘ läuft – Timer auf Website“ mit „Wechseln zu …“ (nur mit Regel).
/// Mit `calendarMeetingHintEnabled` aus (Einstellungen › Mitteilungen) bleibt die Zeile leer und
/// nimmt im Stapel keinen Platz ein. Ohne `AppSettings` in der Umgebung (Vorschau) wird sie gezeigt.
struct TodayMeetingHintRow: View {
    let hint: TodayData.MeetingHint
    let theme: DesignTheme
    let actions: TodayActions
    var dismiss: () -> Void = {}

    @Environment(AppSettings.self) private var settings: AppSettings?

    var body: some View {
        if settings?.calendarMeetingHintEnabled ?? true {
            row
        }
    }

    private var row: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hint.event.calendarColor)
            (Text("Termin ‚\(hint.event.title)‘ läuft")
                .foregroundStyle(.primary)
             + Text(" – Timer auf \(hint.runningProject.name)")
                .foregroundStyle(.secondary))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            if let target = hint.target {
                Button { actions.start(target) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(target.color)
                        Text("Wechseln zu \(target.name)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(theme.tint(target.color, strong: true), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Timer auf \(target.name) umstellen")
            }
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.tertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Hinweis ausblenden")
            .accessibilityLabel("Hinweis ausblenden")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 34)
        .background(theme.tint(hint.event.calendarColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: - Liste „Termine heute“

/// Kompakte Terminliste unter der Tagesleiste: Zeit, Titel, Kalenderfarbe; rechts „Als Eintrag“
/// bzw. „✓ erfasst“. Ganztägige Termine als eine Hinweiszeile darüber.
struct TodayEventList: View {
    let data: TodayData
    let theme: DesignTheme
    let actions: TodayActions

    @State private var isExpanded = false

    /// So viele Termine ohne „weitere“.
    static let collapsedLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Termine heute")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.tertiary)
                if !data.allDayEvents.isEmpty {
                    allDay
                }
                Spacer(minLength: 0)
            }
            .frame(height: 18)
            ForEach(visibleEvents) { event in
                row(event)
            }
            if hiddenCount > 0 || isExpanded, data.events.count > Self.collapsedLimit {
                Button(isExpanded ? "Weniger anzeigen" : "Alle \(data.events.count) Termine anzeigen") {
                    isExpanded.toggle()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 13)
            }
        }
    }

    /// Ganztägig: „Ganztägig: Tag der offenen Tür“ (mehrere mit „·“).
    private var allDay: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(data.allDayEvents[0].calendarColor)
                .frame(width: 6, height: 6)
            Text("Ganztägig: " + data.allDayEvents.map(\.title).joined(separator: " · "))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help(data.allDayEvents.map { "\($0.title) (\($0.calendarTitle))" }.joined(separator: "\n"))
    }

    /// Eingeklappt höchstens `collapsedLimit` Termine ab dem ersten, der noch zählt: vorbei und
    /// schon erfasst zählt nicht mehr; sonst die letzten.
    private var visibleEvents: [TodayData.EventItem] {
        let events = data.events
        guard !isExpanded, events.count > Self.collapsedLimit else { return events }
        let firstRelevant = events.firstIndex { !($0.end <= data.now && $0.isCaptured) }
            ?? max(0, events.count - Self.collapsedLimit)
        let start = min(firstRelevant, events.count - Self.collapsedLimit)
        return Array(events[start..<(start + Self.collapsedLimit)])
    }

    private var hiddenCount: Int {
        max(0, data.events.count - visibleEvents.count)
    }

    private func row(_ event: TodayData.EventItem) -> some View {
        let isCurrent = event.isCurrent(now: data.now)
        let isPast = event.end <= data.now
        return HStack(alignment: .center, spacing: 10) {
            Capsule()
                .fill(event.calendarColor.opacity(0.75))
                .frame(width: 3, height: 16)
            Text("\(TodayFormat.clock(event.start))–\(TodayFormat.clock(event.end))")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(event.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isPast && !isCurrent ? .secondary : .primary)
                .lineLimit(1)
            if isCurrent {
                Text("läuft")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(event.calendarColor)
            }
            if let project = event.project {
                HStack(spacing: 4) {
                    Circle().fill(project.color).frame(width: 6, height: 6)
                    Text(project.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .help("Regel: Termin gehört zu \(project.name)")
            }
            Spacer(minLength: 8)
            Text(event.calendarTitle)
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiary)
                .lineLimit(1)
            if event.isCaptured {
                Text("✓ erfasst")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 104, alignment: .trailing)
            } else {
                Button { actions.captureEvent(event) } label: {
                    Label("Als Eintrag", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .overlay(Capsule().stroke(theme.hairline, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(minWidth: 104, alignment: .trailing)
                .help("„\(event.title)“ als Eintrag übernehmen")
            }
        }
        .frame(height: 24)
        .accessibilityElement(children: .combine)
    }
}
