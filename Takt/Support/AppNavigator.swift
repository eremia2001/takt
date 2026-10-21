import Foundation
import Observation

/// Aktionen, die Menüs (App-Menü, Befehlspalette) anfordern und die zuständige Ansicht ausführt.
/// `MainView` wechselt dafür in den passenden Bereich; konsumiert dort niemand die Anforderung,
/// übernimmt `MainView` selbst (Sheet bzw. Hinweis).
enum AppAction: String, CaseIterable {
    case exportEntriesCSV, exportSummaryCSV, exportTimesheetPDF, importToggl, planBlock, newProject, newEntry
}

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
    /// Gewünschte Aktion (Export, Import, Neuer Eintrag …), siehe `AppAction`.
    var requestedAction: AppAction?
    /// Gewünschtes Hilfe-Thema (Kennung wie in `HelpContent`); das Hilfe-Fenster öffnet `HelpCenter`.
    var requestedHelpTopic: String?
    /// Einführung (Onboarding) zeigen; `MainView` öffnet das Sheet.
    var isOnboardingRequested = false
    /// Zählt bei jedem Wunsch „Befehlspalette umschalten“ (App-Menü ⌘K) hoch; `MainView` beobachtet ihn.
    private(set) var paletteToggleRevision = 0
    /// Ob die Befehlspalette gerade offen ist (setzt `MainView`). Solange sie offen ist, sind die
    /// Menükürzel ⌘1–3, ⌘N … aus, damit ⌘1–9 der Palette gehören.
    var isPaletteShown = false
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

    func request(action: AppAction) {
        requestedAction = action
        revision += 1
    }

    /// Öffnet das Hilfe-Fenster mit dem Thema (unbekannte Kennungen → „Erste Schritte“).
    func request(helpTopic: String) {
        requestedHelpTopic = helpTopic
        revision += 1
        HelpCenter.shared.show(topicID: helpTopic)
    }

    func requestOnboarding() {
        isOnboardingRequested = true
        revision += 1
    }

    func togglePalette() {
        paletteToggleRevision += 1
    }

    @discardableResult
    func consumeAction() -> AppAction? {
        defer { requestedAction = nil }
        return requestedAction
    }

    @discardableResult
    func consumeHelpTopic() -> String? {
        defer { requestedHelpTopic = nil }
        return requestedHelpTopic
    }

    /// `true`, wenn die Einführung angefordert war (und setzt den Wunsch zurück).
    func consumeOnboarding() -> Bool {
        defer { isOnboardingRequested = false }
        return isOnboardingRequested
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
