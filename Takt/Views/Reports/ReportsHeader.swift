import SwiftUI
import TaktCore

/// Kopfzeile der Berichte: Art des Zeitraums, Blättern, Titel bzw. Datumsauswahl,
/// rechts Export-Menü und Toggl-Import.
/// Bricht in zwei Zeilen um, wenn das Fenster schmal ist.
struct ReportsHeader: View {
    @Binding var period: ReportPeriod
    /// Gewähltes Kalenderjahr im Reiter „Jahr“; `nil` = `period` gilt.
    @Binding var year: Int?
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
            stepButton("chevron.left", help: year == nil ? "Vorheriger Zeitraum" : "Vorheriges Jahr") {
                if let year { self.year = year - 1 } else { period = period.previous(calendar: calendar) }
            }
            stepButton("chevron.right", help: year == nil ? "Nächster Zeitraum" : "Nächstes Jahr") {
                if let year { self.year = year + 1 } else { period = period.next(calendar: calendar) }
            }
            if let year {
                // `verbatim`: sonst setzt die Lokalisierung einen Tausenderpunkt („2.026“).
                Text(verbatim: String(year))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.leading, 6)
            } else if case .custom = period {
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
            if !isCurrent, kindBinding.wrappedValue != .custom {
                Button {
                    if year != nil {
                        year = calendar.component(.year, from: now)
                    } else {
                        period = ReportPeriodKind(period).period(from: .day(now), now: now, calendar: calendar)
                    }
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
        if let year { return year == calendar.component(.year, from: now) }
        return period.interval(calendar: calendar).contains(now)
    }

    /// Der gezeigte Zeitraum; im Reiter „Jahr“ das ganze Jahr als freier Zeitraum.
    private var effectivePeriod: ReportPeriod {
        if let year { return .custom(ReportsYear.interval(year, calendar: calendar)) }
        return period
    }

    /// Wechsel der Art behält den Bezug: Jahr → Monat landet im heutigen Monat (aktuelles Jahr)
    /// bzw. im Januar, Jahr → Zeitraum übernimmt das ganze Jahr.
    private var kindBinding: Binding<ReportPeriodKind> {
        Binding(
            get: { year != nil ? .year : ReportPeriodKind(period) },
            set: { kind in
                let current = effectivePeriod
                if kind == .year {
                    year = ReportsYear.year(for: current.interval(calendar: calendar), now: now, calendar: calendar)
                } else {
                    year = nil
                    period = kind.period(from: current, now: now, calendar: calendar)
                }
            }
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
                if year != nil {
                    Button("Jahr als CSV …", action: actions.exportYear)
                    Button("Einträge als CSV …", action: actions.exportEntries)
                } else {
                    Button("Einträge als CSV …", action: actions.exportEntries)
                    Button("Zusammenfassung als CSV …", action: actions.exportSummary)
                }
                Divider()
                Button("Timesheet als PDF …", action: actions.exportTimesheet)
            } label: {
                pillLabel("Exportieren", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Bericht als CSV-Datei oder Timesheet als PDF speichern")

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
                .help(Self.help(kind))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zeitraum")
    }

    static func help(_ kind: ReportPeriodKind) -> String {
        switch kind {
        case .day: "Bericht für einen Tag"
        case .week: "Bericht für eine Woche (Mo–So), mit Wochenziel, falls eingestellt"
        case .month: "Bericht für einen Kalendermonat"
        case .year: "Jahresübersicht: Monate, Kunden, Tags und Vergleich zum Vorjahr"
        case .custom: "Freier Zeitraum: Start- und Enddatum selbst wählen"
        }
    }
}
