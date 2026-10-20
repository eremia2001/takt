import SwiftUI
import TaktCore

/// Sheet „Aus Toggl importieren“: verbindet `TogglImportContent` mit dem Store.
struct TogglImportSheet: View {
    @Environment(TaktStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TogglImportContent(
            projects: store.projects + store.archivedProjects,
            suggest: { store.suggestedTogglMapping(for: $0) },
            perform: { preview, mapping, markAsBusiness in
                if let count = store.importToggl(preview, projectMapping: mapping, markAsBusiness: markAsBusiness) {
                    return .success(count)
                }
                // Fehler im Sheet zeigen statt als Fenster-Hinweis.
                let message = store.consumeError() ?? "Der Import ist fehlgeschlagen."
                return .failure(.init(message: message))
            },
            close: { dismiss() }
        )
    }
}
