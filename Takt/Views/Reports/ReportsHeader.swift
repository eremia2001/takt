import SwiftUI
import TaktCore

/// Kopfzeile der Berichte: Art des Zeitraums, Blättern, Titel bzw. Datumsauswahl,
/// rechts Export-Menü und Toggl-Import.
/// Bricht in zwei Zeilen um, wenn das Fenster schmal ist.
struct ReportsHeader: View {
    @Binding var period: ReportPeriod
    var now: Date
    var actions: ReportsActions
    let theme: DesignTheme
    var calendar: Calendar = .current

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                periodControls
                Spacer(minLength: 12)
                trailing(compact: false)
            }
            // Etwas schmaler: „Freie Tage“ nur als Symbol, alles bleibt in einer Zeile.
            HStack(spacing: 10) {
                periodControls
                Spacer(minLength: 4)
                trailing(compact: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    ReportsKindPicker(selection: kindBinding, theme: theme)
                    Spacer(minLength: 12)
                    trailing(compact: false)
                }
                HStack(spacing: 14) {
                    navigation
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Zeitraum

    private var periodControls: some View {
        HStack(spacing: 14) {
            ReportsKindPicker(selection: kindBinding, theme: theme)
            navigation
        }
    }

    private var navigation: some View {
        HStack(spacing: 4) {
            stepButton("chevron.left", help: "Vorheriger Zeitraum") {
                period = period.previous(calendar: calendar)
            }
            stepButton("chevron.right", help: "Nächster Zeitraum") {
                period = period.next(calendar: calendar)
            }
            if case .custom = period {
                customRange
                    .padding(.leading, 6)
            } else {
                Text(period.title(calendar: calendar))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.leading, 6)
            }
            // Beim freien Zeitraum wählt man die Daten selbst – dort kein „Heute“.
            if !isCurrent, ReportPeriodKind(period) != .custom {
                Button {
                    period = ReportPeriodKind(period).period(from: .day(now), now: now, calendar: calendar)
                } label: {
                    Text("Heute")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .overlay(Capsule().stroke(theme.hairline, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
                .help("Zum aktuellen Zeitraum springen")
            }
        }
    }

    private func stepButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    /// Start- und Enddatum eines freien Zeitraums (beide Tage eingeschlossen).
    private var customRange: some View {
        HStack(spacing: 6) {
            DatePicker("Start", selection: startBinding, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .fixedSize()
            Text("–")
                .foregroundStyle(.secondary)
            DatePicker("Ende", selection: endBinding, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .fixedSize()
        }
    }

    private var isCurrent: Bool {
        period.interval(calendar: calendar).contains(now)
    }

    private var kindBinding: Binding<ReportPeriodKind> {
        Binding(
            get: { ReportPeriodKind(period) },
            set: { period = $0.period(from: period, now: now, calendar: calendar) }
        )
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { period.interval(calendar: calendar).start },
            set: { value in
                let interval = period.interval(calendar: calendar)
                let start = calendar.startOfDay(for: value)
                var end = interval.end
                if end <= start { end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400) }
                period = .custom(DateInterval(start: start, end: end))
            }
        )
    }

    /// Ende als letzter enthaltener Tag; gespeichert wird exklusiv (Mitternacht danach).
    private var endBinding: Binding<Date> {
        Binding(
            get: {
                let interval = period.interval(calendar: calendar)
                return interval.end > interval.start ? interval.end.addingTimeInterval(-1) : interval.start
            },
            set: { value in
                let interval = period.interval(calendar: calendar)
                let lastDay = calendar.startOfDay(for: value)
                let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay.addingTimeInterval(86_400)
                let start = min(interval.start, lastDay)
                period = .custom(DateInterval(start: start, end: end))
            }
        )
    }

    // MARK: Rechts

    private func trailing(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            Button(action: actions.editDaysOff) {
                if compact {
                    Image(systemName: "sun.max")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(theme.hairline, lineWidth: 1))
                        .contentShape(Circle())
                } else {
                    pillLabel("Freie Tage …", systemImage: "sun.max")
                }
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Freie Tage: Urlaub, Krankheit und Feiertage eintragen – sie zählen nicht als Arbeitstage")
            .accessibilityLabel("Freie Tage")

            Menu {
                Button("Einträge als CSV …", action: actions.exportEntries)
                Button("Zusammenfassung als CSV …", action: actions.exportSummary)
            } label: {
                pillLabel("Exportieren", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Bericht als CSV-Datei speichern")

            Button(action: actions.importToggl) {
                pillLabel("Toggl importieren …", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Einträge aus einem Toggl-Detailexport (CSV) übernehmen")
        }
    }

    private func pillLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .overlay(Capsule().stroke(theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
    }
}

/// Segment im Stil der Tabs im Fensterkopf: gewählte Kapsel auf `track`, sonst nur Text.
struct ReportsKindPicker: View {
    @Binding var selection: ReportPeriodKind
    let theme: DesignTheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ReportPeriodKind.allCases) { kind in
                let isSelected = kind == selection
                Button {
                    selection = kind
                } label: {
                    Text(kind.title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(isSelected ? theme.track : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zeitraum")
    }
}
