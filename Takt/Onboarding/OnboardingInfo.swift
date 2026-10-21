import Foundation

/// Wann Einführung bzw. Hinweis „Neu: …“ erscheinen.
///
/// - Neue Nutzer (keine Projekte, Einführung nicht abgeschlossen): Einführung als Sheet.
/// - Keine Projekte (z. B. alles gelöscht): Einführung höchstens einmal je App-Start.
/// - Bestehende Nutzer mit Projekten: keine Einführung, stattdessen einmalig der Hinweis
///   „Neu: Befehlspalette ⌘K …“ unter dem Fensterkopf – bis `onboardingVersion` den aktuellen
///   Stand erreicht (Ausblenden, Fertig oder Überspringen setzen ihn).
@MainActor
enum OnboardingInfo {
    /// Stand von Einführung und Hinweis. Erhöhen, wenn es wieder etwas Neues zu zeigen gibt.
    static let currentVersion = 1

    /// Schon in diesem App-Start gezeigt (damit es nicht bei jedem neuen Fenster erscheint).
    private static var shownThisLaunch = false

    /// Ohne Projekte (auch nach abgeschlossener Einführung) einmal je App-Start; nie, wenn die
    /// Datenbank nicht geöffnet werden konnte (dann fehlen Projekte nur scheinbar).
    static func shouldShowOnboarding(hasProjects: Bool, databaseFailed: Bool) -> Bool {
        !databaseFailed && !shownThisLaunch && !hasProjects
    }

    static func markShown() {
        shownThisLaunch = true
    }

    static func shouldShowWhatsNew(seenVersion: Int) -> Bool {
        seenVersion < currentVersion
    }
}
