import SwiftUI
import TaktCore

// Ansicht „Berichte“ in der Formensprache von „Heute“. Von oben nach unten:
//   Kopfzeile: Tag · Woche · Monat · Zeitraum, Blättern, Titel; rechts Export und Toggl-Import.
//   Kennzahlen: Gesamt · Business/Privat · Abrechenbar · Umsatz; in der Woche ggf. Wochenziel.
//   Verlauf: gestapelte Balken in Projektfarben, freie Tage schraffiert, Fokus-Kennzahlen darüber.
//   Projekte: Tabelle mit Summenzeile, Zeilen klappen Aufschlüsselung nach Tag und Einträge auf.
// Rein darstellend: Daten kommen als `ReportsData`, Aktionen als `ReportsActions`.

struct ReportsScreen: View {
    @Binding var period: ReportPeriod
    /// `nil`, solange noch nichts geladen ist.
    let data: ReportsData?
    var now: Date = .now
    var notice: String?
    var actions = ReportsActions()
    /// Nur für das Render-Harness: aufgeklappte Projekte und überfahrener Balken.
    var initiallyExpanded: Set<UUID> = []
    var initialHover: Date?

    @Environment(\.colorScheme) private var scheme
    private var theme: DesignTheme { DesignTheme(scheme: scheme) }

    /// Seitlicher Rand des Inhalts (wie „Heute“).
    static let sideInset: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReportsHeader(period: $period, now: now, actions: actions, theme: theme)
                .padding(.horizontal, Self.sideInset)
                .padding(.top, 4)
                .padding(.bottom, 16)

            if let data, !data.isEmpty {
                ScrollView {
                    content(data)
                        .padding(.horizontal, Self.sideInset)
                        .padding(.bottom, 24)
                }
                .scrollIndicators(.automatic)
            } else if let data {
                emptyState(data)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .top) {
            // Kurze Bestätigung (z. B. nach dem Export) schwebt über dem Inhalt, ohne ihn zu verschieben.
            if let notice {
                toast(notice)
                    .padding(.top, 50)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func toast(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(theme.surface, in: Capsule())
            .overlay(Capsule().stroke(theme.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(theme.dark ? 0.35 : 0.10), radius: 10, y: 3)
            .frame(maxWidth: 420)
            .accessibilityAddTraits(.isStaticText)
    }

    private func content(_ data: ReportsData) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            ReportsMetrics(data: data, theme: theme)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Verlauf")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    focusLine(data)
                }
                ReportsChart(data: data, theme: theme, initialHover: initialHover)
                    // Gleiche Daten → gleicher Zustand; neuer Zeitraum → Hover zurücksetzen.
                    .id(data.interval)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Projekte")
                    .font(.system(size: 13, weight: .semibold))
                ReportsProjectTable(data: data, theme: theme, initiallyExpanded: initiallyExpanded)
                    .id(data.interval)
            }
        }
    }

    /// „n Wechsel · längster Block h:mm · n Arbeitstage (1 frei) · Ø h:mm pro Arbeitstag“ –
    /// bewusst leise. Arbeitstage = Mo–Fr ohne freie Tage; beim einzelnen Tag ohne Ø.
    private func focusLine(_ data: ReportsData) -> some View {
        let report = data.report
        var isDay = false
        if case .day = report.period { isDay = true }
        let freeCount = report.daysOff.count
        return HStack(spacing: 8) {
            Text("\(report.focus.switches) Wechsel")
            Text("·")
            Text("längster Block \(ReportsFormat.duration(report.focus.longestBlock))")
            if !isDay || freeCount > 0 || report.workdays == 0 {
                Text("·")
                if isDay, let dayOff = report.daysOff.first {
                    Text("frei: \(dayOff.kind.title)")
                } else {
                    Text(ReportsFormat.workdays(report.workdays) + (freeCount > 0 ? " (\(freeCount) frei)" : ""))
                }
            }
            if !isDay, report.workdays > 0 {
                Text("·")
                Text("Ø \(ReportsFormat.duration(report.averagePerWorkday)) pro Arbeitstag")
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(theme.tertiary)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    /// Leerer Zeitraum; ein einzelner freier Tag sagt, warum („Freier Tag · Urlaub“).
    private func emptyState(_ data: ReportsData) -> some View {
        var dayOff: DayOff?
        if case .day = data.report.period { dayOff = data.report.daysOff.first }
        return VStack(spacing: 6) {
            Image(systemName: dayOff == nil ? "chart.bar" : "sun.max")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.tertiary)
            if let dayOff {
                Text("Freier Tag · \(dayOff.kind.title)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                if let note = dayOff.note {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.tertiary)
                }
            } else {
                Text("Keine Einträge in diesem Zeitraum")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }
}
