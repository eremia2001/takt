import Foundation
import Observation

/// Zentrale Navigationswünsche, damit Befehlspalette, Menüleiste und Mitteilungen Bereiche
/// und Berichtszeiträume anfordern können, ohne die Views direkt zu kennen.
///
/// Verwendung: ein Aufrufer setzt eine Anforderung (`request…`), die zuständige View beobachtet
/// das Feld, führt sie aus und setzt es per `consume…` zurück.
@MainActor
@Observable
final class AppNavigator {
    /// Gewünschter Bereich im Hauptfenster (Heute, Berichte, Projekte).
    var requestedSection: AppSection?
    /// Gewünschter Zeitraum in den Berichten (Tag, Woche, Monat, Jahr); `custom` wird nicht angefordert.
    var requestedReportKind: ReportPeriodKind?
    /// Gewünschter Reiter in den Einstellungen (Kennung wie in `SettingsView`, z. B. "notifications").
    var requestedSettingsTab: String?
    /// Zähler, der bei jeder Anforderung hochzählt – für Views, die auf jede Anforderung reagieren wollen.
    private(set) var revision = 0

    func request(section: AppSection) {
        requestedSection = section
        revision += 1
    }

    func request(reportKind: ReportPeriodKind) {
        requestedSection = .reports
        requestedReportKind = reportKind
        revision += 1
    }

    func request(settingsTab: String) {
        requestedSettingsTab = settingsTab
        revision += 1
    }

    @discardableResult
    func consumeSection() -> AppSection? {
        defer { requestedSection = nil }
        return requestedSection
    }

    @discardableResult
    func consumeReportKind() -> ReportPeriodKind? {
        defer { requestedReportKind = nil }
        return requestedReportKind
    }

    @discardableResult
    func consumeSettingsTab() -> String? {
        defer { requestedSettingsTab = nil }
        return requestedSettingsTab
    }
}
