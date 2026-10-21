import SwiftUI
import TaktCore

/// Verbindet `OnboardingView` mit Store (Projekt anlegen), Einstellungen (Abschluss-Flags,
/// Kurzbefehle) und den Freigaben. Wird von `MainView` als Sheet gezeigt.
struct OnboardingSheet: View {
    @Environment(TaktStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(CalendarService.self) private var calendarService: CalendarService?
    @Environment(\.dismiss) private var dismiss

    var openHelp: (String) -> Void = { HelpCenter.shared.show(topicID: $0) }

    @State private var permissions: PermissionCenter?

    var body: some View {
        OnboardingView(
            context: HelpContext.current(settings),
            existingProjects: store.projects.map { OnboardingProject(id: $0.id, name: $0.name, colorHex: $0.colorHex) },
            colors: ProjectPalette.colors,
            suggestedColor: ProjectPalette.next(after: store.projects.map(\.colorHex)),
            createProject: create,
            openHelp: openHelp,
            finish: { _ in close() }
        ) {
            if let permissions {
                PermissionList(center: permissions)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            if permissions == nil { permissions = PermissionCenter(calendarService: calendarService) }
        }
    }

    /// Fertig und Überspringen schließen gleichermaßen ab: Die Einführung kommt nicht ungefragt wieder.
    private func close() {
        settings.onboardingCompleted = true
        settings.onboardingVersion = OnboardingInfo.currentVersion
        dismiss()
    }

    private func create(name: String, colorHex: String, isBusiness: Bool) -> String? {
        let project = Project(
            name: name,
            colorHex: colorHex,
            isBusiness: isBusiness,
            sortOrder: store.nextSortOrder
        )
        if store.saveProject(project) { return nil }
        return store.consumeError() ?? "Das Projekt konnte nicht angelegt werden."
    }
}
