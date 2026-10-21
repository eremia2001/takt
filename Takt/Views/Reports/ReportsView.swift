import Observation
import SwiftUI
import TaktCore

/// Bereich „Berichte“: verbindet `ReportsScreen` mit Store, Einstellungen, CSV-Export und
/// Toggl-Import. Lädt den Bericht neu bei Wechsel von Zeitraum oder Einstellungen, bei jeder
/// Datenänderung (auch aus dem Widget) und – nur solange ein Timer läuft – minütlich.
/// Im Reiter „Jahr“ (`year != nil`) gilt dasselbe für den Jahresbericht.
/// Reagiert auf `AppNavigator.requestedReportKind` (Befehlspalette, Menüleiste) mit einem Wechsel
/// des Zeitraums.
struct ReportsView: View {
    @Environment(TaktStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(AppNavigator.self) private var navigator

    @State private var period: ReportPeriod = .week(.now)
    @State private var data: ReportsData?
    /// Gewähltes Jahr im Reiter „Jahr“; `nil` = `period` gilt.
    @State private var year: Int?
    @State private var yearData: YearReportsData?
    @State private var notice: String?
    @State private var noticeID = 0
    @State private var isImportShown = false
    @State private var isDaysOffShown = false
    /// Zeitraum, mit dem „Timesheet als PDF“ geöffnet wird; `nil` = Sheet zu.
    @State private var timesheetInterval: TimesheetInterval?
    /// Erst beim Erscheinen angelegt, damit nicht jede Neuerzeugung der View einen Beobachter registriert.
    @State private var changes: ReportsChangeMonitor?

    var body: some View {
        // Eine einzige TimelineView (gleiche Identität, aufgeklappte Zeilen bleiben erhalten);
        // sie tickt nur, solange ein Timer läuft – im Takt des Eintrags, damit `h:mm` zur
        // vollen Minute springt.
        TimelineView(RunningMinuteSchedule(start: store.running?.entry.startedAt)) { context in
            let isRunning = store.running != nil
            screen(now: isRunning ? context.date : .now)
                .onChange(of: context.date) {
                    if isRunning { reload(now: context.date) }
                }
        }
        .onAppear {
            if changes == nil { changes = ReportsChangeMonitor() }
            // Eine Anforderung kann vor dem Erscheinen gekommen sein (Bereichswechsel).
            applyRequestedKind()
            reload()
        }
        .onChange(of: navigator.revision) { applyRequestedKind() }
        .onChange(of: period) { reload() }
        .onChange(of: year) { reload() }
        .onChange(of: settings.rounding) { reload() }
        .onChange(of: settings.defaultHourlyRate) { reload() }
        .onChange(of: settings.currencyCode) { reload() }
        .onChange(of: settings.weeklyGoalHours) { reload() }
        .onChange(of: changes?.revision) { reload() }
        .onChange(of: store.running) { reload() }
        .sheet(isPresented: $isImportShown, onDismiss: { reload() }) {
            TogglImportSheet()
        }
        .sheet(isPresented: $isDaysOffShown, onDismiss: { reload() }) {
            DaysOffSheet(month: daysOffMonth)
        }
        .sheet(item: $timesheetInterval) { request in
            TimesheetExportSheet(initialInterval: request.interval) { name in
                showNotice("Gespeichert: \(name)")
            }
        }
    }

    /// Führt eine angeforderte Art des Zeitraums aus (immer bezogen auf heute).
    /// - Returns: `true`, wenn sich etwas geändert hat (das Neuladen übernimmt dann `onChange`).
    @discardableResult
    private func applyRequestedKind() -> Bool {
        guard let kind = navigator.consumeReportKind() else { return false }
        let now = Date.now
        switch kind {
        case .year:
            let current = Calendar.current.component(.year, from: now)
            guard year != current else { return false }
            year = current
        case .day, .week, .month:
            let target = kind.period(from: .day(now), now: now, calendar: .current)
            guard year != nil || period != target else { return false }
            year = nil
            period = target
        case .custom:
            // Wird nicht angefordert; zur Sicherheit den gezeigten Zeitraum als freien übernehmen.
            let interval = year.map { ReportsYear.interval($0, calendar: .current) } ?? period.interval(calendar: .current)
            year = nil
            period = .custom(interval)
        }
        return true
    }

    private func screen(now: Date) -> some View {
        ReportsScreen(
            period: $period,
            data: data,
            year: $year,
            yearData: yearData,
            now: now,
            notice: notice,
            actions: ReportsActions(
                exportEntries: { export(.entries) },
                exportSummary: { export(.summary) },
                exportYear: { export(.year) },
                exportTimesheet: { timesheetInterval = TimesheetInterval(interval: shownInterval) },
                importToggl: { isImportShown = true },
                editDaysOff: { isDaysOffShown = true }
            )
        )
    }

    // MARK: Laden

    private func reload(now: Date = .now) {
        if let year {
            reloadYear(year, now: now)
            return
        }
        guard let report = store.report(
            for: period,
            rounding: settings.rounding,
            defaultHourlyRate: settings.defaultHourlyRate,
            weeklyGoal: settings.weeklyGoal,
            now: now
        ) else { return }
        let entries = store.entries(in: report.interval).sorted { $0.startedAt < $1.startedAt }
        data = ReportsData(
            report: report,
            entries: entries,
            rounding: settings.rounding,
            currencyCode: settings.currencyCode,
            now: now
        )
    }

    /// Jahresbericht und Einträge des Jahres (für den Monatsverlauf je Projekt).
    private func reloadYear(_ year: Int, now: Date) {
        guard let report = store.yearReport(
            year: year,
            rounding: settings.rounding,
            defaultHourlyRate: settings.defaultHourlyRate,
            now: now
        ) else { return }
        yearData = YearReportsData(
            report: report,
            entries: store.entries(in: report.interval),
            rounding: settings.rounding,
            currencyCode: settings.currencyCode,
            now: now
        )
    }

    /// Gezeigter Zeitraum (im Reiter „Jahr“ das ganze Jahr).
    private var shownInterval: DateInterval {
        year.map { ReportsYear.interval($0, calendar: .current) } ?? period.interval(calendar: .current)
    }

    /// Monat für „Freie Tage“: enthält der Zeitraum heute, der heutige, sonst der seines Anfangs.
    private var daysOffMonth: Date {
        let interval = year.map { ReportsYear.interval($0, calendar: .current) } ?? period.interval(calendar: .current)
        return interval.contains(.now) ? .now : interval.start
    }

    // MARK: Export

    private func export(_ kind: CSVExporter.Kind) {
        let now = Date.now
        reload(now: now)
        if let year {
            exportYear(year, kind: kind, now: now)
            return
        }
        guard let data else { return }
        let content: String
        switch kind {
        case .entries:
            content = CSVExport.entries(
                data.entries,
                projects: Array(store.projectsById.values),
                rounding: settings.rounding,
                calendar: .current,
                defaultHourlyRate: settings.defaultHourlyRate,
                now: now
            )
        case .summary, .year:
            content = CSVExport.summary(data.report, calendar: .current)
        }
        save(content, name: CSVExporter.fileName(kind == .year ? .summary : kind, period: period))
    }

    /// Reiter „Jahr“: Jahresübersicht (Monate + Kunden) oder alle Einträge des Jahres.
    private func exportYear(_ year: Int, kind: CSVExporter.Kind, now: Date) {
        guard let yearData, yearData.year == year else { return }
        let content: String
        switch kind {
        case .entries:
            content = CSVExport.entries(
                store.entries(in: yearData.report.interval).sorted { $0.startedAt < $1.startedAt },
                projects: Array(store.projectsById.values),
                rounding: settings.rounding,
                calendar: .current,
                defaultHourlyRate: settings.defaultHourlyRate,
                now: now
            )
        case .summary, .year:
            content = CSVExporter.yearCSV(yearData)
        }
        save(content, name: CSVExporter.fileName(kind == .entries ? .entries : .year, year: year))
    }

    private func save(_ content: String, name: String) {
        Task { @MainActor in
            do {
                if let url = try await CSVExporter.save(content, suggestedName: name) {
                    showNotice("Gespeichert: \(url.lastPathComponent)")
                }
            } catch {
                store.lastError = "Die Datei konnte nicht gespeichert werden: \(error.localizedDescription)"
            }
        }
    }

    /// Kurze Bestätigung im Kopf, verschwindet nach 3 Sekunden.
    private func showNotice(_ text: String) {
        noticeID += 1
        let id = noticeID
        withAnimation(.easeOut(duration: 0.2)) { notice = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard noticeID == id else { return }
            withAnimation(.easeIn(duration: 0.3)) { notice = nil }
        }
    }
}

/// Anlass für das Timesheet-Sheet (`sheet(item:)` braucht `Identifiable`).
struct TimesheetInterval: Identifiable {
    let id = UUID()
    let interval: DateInterval
}

/// Zählt Datenänderungen (Darwin-Notification von App und Widget), damit auch Änderungen an
/// älteren Einträgen den Bericht neu laden – der Store hält nur „heute“ vor.
@MainActor
@Observable
final class ReportsChangeMonitor {
    private(set) var revision = 0
    @ObservationIgnored private var observation: ChangeObservation?

    init() {
        observation = ChangeNotifier.observe { [weak self] in
            MainActor.assumeIsolated { self?.revision += 1 }
        }
    }
}

/// Minütlicher Takt ab `start`, solange ein Timer läuft; ohne `start` genau ein Eintrag (kein Ticken).
struct RunningMinuteSchedule: TimelineSchedule {
    var start: Date?

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        guard let start else {
            var delivered = false
            return AnyIterator {
                defer { delivered = true }
                return delivered ? nil : startDate
            }
        }
        var iterator = PeriodicTimelineSchedule(from: start, by: 60).entries(from: startDate, mode: mode).makeIterator()
        return AnyIterator { iterator.next() }
    }
}
