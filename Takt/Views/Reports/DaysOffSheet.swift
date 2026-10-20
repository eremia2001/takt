import SwiftUI
import TaktCore

// Sheet „Freie Tage“: Monatsraster (Mo–So). Klick auf einen Tag markiert ihn als frei (Art wie
// zuletzt gewählt), ein erneuter Klick auf den gewählten Tag entfernt die Markierung. Darunter
// Art und Notiz des gewählten Tags. Freie Tage verringern die Arbeitstage im Bericht und damit
// das Wochenziel. Geöffnet aus den Berichten („Freie Tage …“) und aus „Heute“ („Heute frei …“).

/// Verbindet `DaysOffContent` mit dem Store.
struct DaysOffSheet: View {
    @Environment(TaktStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Monat, der zuerst gezeigt wird.
    var month: Date = .now
    /// Vorausgewählter Tag (z. B. heute), sonst keiner.
    var selected: Date?

    var body: some View {
        DaysOffContent(
            month: month,
            selected: selected,
            load: { store.daysOff(in: $0) },
            set: { date, kind, note in store.setDayOff(date: date, kind: kind, note: note) },
            remove: { store.removeDayOff(date: $0) },
            done: { dismiss() }
        )
    }
}

/// Inhalt des Sheets, ohne Store (Render-Harness).
struct DaysOffContent: View {
    let load: (DateInterval) -> [DayOff]
    let set: (Date, DayOffKind, String?) -> Void
    let remove: (Date) -> Void
    let done: () -> Void
    var today: Date = .now

    @State private var month: Date
    @State private var selected: Date?
    @State private var daysOff: [String: DayOff] = [:]
    /// Art für neu markierte Tage und Anzeige des gewählten Tags.
    @State private var kind: DayOffKind = .vacation
    @State private var note = ""
    /// Notiz geändert, aber noch nicht gesichert.
    @State private var isNoteDirty = false

    @Environment(\.colorScheme) private var scheme
    private var theme: DesignTheme { DesignTheme(scheme: scheme) }
    private let calendar = DaysOffContent.mondayCalendar

    init(
        month: Date,
        selected: Date? = nil,
        today: Date = .now,
        load: @escaping (DateInterval) -> [DayOff],
        set: @escaping (Date, DayOffKind, String?) -> Void,
        remove: @escaping (Date) -> Void,
        done: @escaping () -> Void
    ) {
        self.load = load
        self.set = set
        self.remove = remove
        self.done = done
        self.today = today
        let calendar = Self.mondayCalendar
        _month = State(initialValue: calendar.dateInterval(of: .month, for: month)?.start ?? month)
        _selected = State(initialValue: selected.map { calendar.startOfDay(for: $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            grid
            Rectangle().fill(theme.hairline).frame(height: 1)
            detail
            footer
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            reload()
            // Vorausgewählter freier Tag: Art und Notiz übernehmen.
            if let selected, let off = daysOff[DayOff.key(for: selected, calendar: calendar)] {
                select(selected, off)
            }
        }
        .onChange(of: month) { reload() }
    }

    // MARK: Kopf

    private var header: some View {
        HStack(spacing: 4) {
            Text("Freie Tage")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            stepButton("chevron.left", help: "Vorheriger Monat") { shiftMonth(-1) }
            Text(Self.monthTitle(month, calendar: calendar))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: 110)
            stepButton("chevron.right", help: "Nächster Monat") { shiftMonth(1) }
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

    // MARK: Raster

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 4), count: 7) }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"], id: \.self) { name in
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.tertiary)
                    .frame(height: 16)
            }
            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                if let day {
                    cell(day)
                } else {
                    Color.clear.frame(height: 40)
                }
            }
        }
    }

    /// Tage des Monats, vorne mit Lücken bis zum Montag.
    private var cells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let offset = (calendar.component(.weekday, from: interval.start) + 5) % 7
        var days: [Date?] = Array(repeating: nil, count: offset)
        var day = interval.start
        while day < interval.end {
            days.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? interval.end
        }
        return days
    }

    private func cell(_ day: Date) -> some View {
        let off = daysOff[DayOff.key(for: day, calendar: calendar)]
        let isSelected = selected.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let isWeekend = calendar.isDateInWeekend(day)
        return Button { tap(day) } label: {
            VStack(spacing: 1) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 13, weight: isToday ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(off != nil ? AnyShapeStyle(.primary)
                                     : isWeekend ? AnyShapeStyle(theme.tertiary) : AnyShapeStyle(.primary))
                Text(off.map { Self.shortTitle($0.kind) } ?? " ")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(off.map { Self.color($0.kind) } ?? .clear)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(off.map { theme.tint(Self.color($0.kind), strong: isSelected) } ?? (isSelected ? theme.track : .clear))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? AnyShapeStyle(.primary.opacity(0.55))
                            : isToday ? AnyShapeStyle(Color.accentColor.opacity(0.7)) : AnyShapeStyle(.clear),
                            lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(off == nil ? "Als frei markieren" : (isSelected ? "Markierung entfernen" : "\(off!.kind.title) – auswählen"))
        .accessibilityLabel(Self.dayTitle(day, calendar: calendar) + (off.map { ", \($0.kind.title)" } ?? ""))
    }

    // MARK: Gewählter Tag

    @ViewBuilder
    private var detail: some View {
        if let selected {
            let off = daysOff[DayOff.key(for: selected, calendar: calendar)]
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(Self.dayTitle(selected, calendar: calendar))
                        .font(.system(size: 13, weight: .semibold))
                    if off == nil {
                        Text("kein freier Tag")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Picker("Art", selection: kindBinding) {
                    ForEach(DayOffKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                TextField("Notiz", text: $note, prompt: Text("Notiz (optional)"))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: note) { isNoteDirty = true }
                    .onSubmit(saveNote)
                HStack {
                    Spacer()
                    if off != nil {
                        Button("Entfernen", role: .destructive) { unmark(selected) }
                    } else {
                        Button("Als frei markieren") { mark(selected) }
                    }
                }
            }
        } else {
            Text("Tag anklicken, um ihn als frei zu markieren. Ein erneuter Klick entfernt die Markierung.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            Text(summary)
                .font(.system(size: 12))
                .foregroundStyle(theme.tertiary)
            Spacer()
            Button("Fertig") {
                saveNote()
                done()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private var summary: String {
        let count = daysOff.count
        let monthName = Self.monthNames[calendar.component(.month, from: month) - 1]
        switch count {
        case 0: return "Keine freien Tage im \(monthName)"
        case 1: return "1 freier Tag im \(monthName)"
        default: return "\(count) freie Tage im \(monthName)"
        }
    }

    /// Art ändern: ein bereits freier Tag wird sofort gesichert.
    private var kindBinding: Binding<DayOffKind> {
        Binding(
            get: { kind },
            set: { newKind in
                kind = newKind
                guard let selected, daysOff[DayOff.key(for: selected, calendar: calendar)] != nil else { return }
                set(selected, newKind, trimmedNote)
                isNoteDirty = false
                reload()
            }
        )
    }

    // MARK: Aktionen

    private func tap(_ day: Date) {
        saveNote()
        let off = daysOff[DayOff.key(for: day, calendar: calendar)]
        let isSelected = selected.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        if off != nil, isSelected {
            unmark(day)
        } else if let off {
            select(day, off)
        } else {
            selected = day
            note = ""
            mark(day)
        }
    }

    private func select(_ day: Date, _ off: DayOff) {
        selected = day
        kind = off.kind
        note = off.note ?? ""
        // `onChange(of: note)` markiert das als geändert; `saveNote` schreibt aber nur echte Änderungen.
    }

    private func mark(_ day: Date) {
        set(day, kind, trimmedNote)
        isNoteDirty = false
        reload()
    }

    private func unmark(_ day: Date) {
        remove(day)
        isNoteDirty = false
        reload()
    }

    private func saveNote() {
        guard isNoteDirty, let selected, let off = daysOff[DayOff.key(for: selected, calendar: calendar)] else { return }
        isNoteDirty = false
        guard trimmedNote != off.note else { return }
        set(selected, off.kind, trimmedNote)
        reload()
    }

    private var trimmedNote: String? {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func shiftMonth(_ delta: Int) {
        saveNote()
        month = calendar.date(byAdding: .month, value: delta, to: month) ?? month
    }

    private func reload() {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return }
        daysOff = Dictionary(load(interval).map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Formate

    /// Kalender mit Montag als Wochenbeginn (für das Raster).
    static var mondayCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    static let monthNames = ["Januar", "Februar", "März", "April", "Mai", "Juni",
                             "Juli", "August", "September", "Oktober", "November", "Dezember"]

    static func monthTitle(_ date: Date, calendar: Calendar) -> String {
        "\(monthNames[calendar.component(.month, from: date) - 1]) \(calendar.component(.year, from: date))"
    }

    /// „Dienstag, 20. Oktober“
    static func dayTitle(_ date: Date, calendar: Calendar) -> String {
        let weekdays = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
        let c = calendar.dateComponents([.weekday, .day, .month], from: date)
        return "\(weekdays[(c.weekday ?? 1) - 1]), \(c.day ?? 0). \(monthNames[(c.month ?? 1) - 1])"
    }

    /// Kurzform im Raster.
    static func shortTitle(_ kind: DayOffKind) -> String {
        kind == .other ? "Sonst." : kind.title
    }

    /// Leise Farbe je Art (nur hier und im Diagramm-Hinweis, nie als Projektfarbe).
    static func color(_ kind: DayOffKind) -> Color {
        switch kind {
        case .vacation: .teal
        case .sick: .pink
        case .holiday: .orange
        case .other: .gray
        }
    }
}
