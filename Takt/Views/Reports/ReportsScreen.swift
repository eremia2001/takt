import SwiftUI
import TaktCore

// Ansicht „Berichte“ in der Formensprache von „Heute“. Von oben nach unten:
//   Kopfzeile: Tag · Woche · Monat · Zeitraum, Blättern, Titel; rechts Export und Toggl-Import.
//   Kennzahlen: Gesamt · Business/Privat · Abrechenbar · Umsatz.
//   Verlauf: gestapelte Balken in Projektfarben, Fokus-Kennzahlen darüber (wie die Tagesleiste).
//   Projekte: Tabelle mit Summenzeile, Zeilen klappen ihre Einträge auf.
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
            } else if data != nil {
                emptyState
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

    /// „n Wechsel · längster Block h:mm · aktive Tage n · Ø h:mm pro Tag“ – bewusst leise.
    private func focusLine(_ data: ReportsData) -> some View {
        let report = data.report
        return HStack(spacing: 8) {
            Text("\(report.focus.switches) Wechsel")
            Text("·")
            Text("längster Block \(ReportsFormat.duration(report.focus.longestBlock))")
            Text("·")
            Text("aktive Tage \(report.activeDays)")
            Text("·")
            Text("Ø \(ReportsFormat.duration(report.averagePerActiveDay)) pro Tag")
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(theme.tertiary)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.tertiary)
            Text("Keine Einträge in diesem Zeitraum")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }
}
