import Observation
import SwiftUI
import TaktCore

/// Bereich „Berichte“: verbindet `ReportsScreen` mit Store, Einstellungen, CSV-Export und
/// Toggl-Import. Lädt den Bericht neu bei Wechsel von Zeitraum oder Einstellungen, bei jeder
/// Datenänderung (auch aus dem Widget) und – nur solange ein Timer läuft – minütlich.
struct ReportsView: View {
    @Environment(TaktStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @State private var period: ReportPeriod = .week(.now)
    @State private var data: ReportsData?
    @State private var notice: String?
    @State private var noticeID = 0
    @State private var isImportShown = false
    @State private var isDaysOffShown = false
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
            reload()
        }
        .onChange(of: period) { reload() }
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
    }

    private func screen(now: Date) -> some View {
        ReportsScreen(
            period: $period,
            data: data,
            now: now,
            notice: notice,
            actions: ReportsActions(
                exportEntries: { export(.entries) },
                exportSummary: { export(.summary) },
                importToggl: { isImportShown = true },
                editDaysOff: { isDaysOffShown = true }
            )
        )
    }

    // MARK: Laden

    private func reload(now: Date = .now) {
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

    /// Monat für „Freie Tage“: enthält der Zeitraum heute, der heutige, sonst der seines Anfangs.
    private var daysOffMonth: Date {
        let interval = period.interval(calendar: .current)
        return interval.contains(.now) ? .now : interval.start
    }

    // MARK: Export

    private func export(_ kind: CSVExporter.Kind) {
        let now = Date.now
        reload(now: now)
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
        case .summary:
            content = CSVExport.summary(data.report, calendar: .current)
        }
        let name = CSVExporter.fileName(kind, period: period)
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
