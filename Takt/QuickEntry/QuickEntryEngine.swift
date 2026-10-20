import Foundation
import TaktCore

/// Bindet die Schnelleingabe außerhalb von „Heute“ (Menüleisten-Popover, schwebendes Fenster)
/// an den Store. Gleiche Regeln wie `TodayView` (Vorschau, Übernehmen, Mehrdeutigkeit auflösen),
/// dort sind sie privat – deshalb hier nachgebaut.
@MainActor
struct QuickEntryEngine {
    let store: TaktStore

    /// Für die Ansichten (`QuickEntryField`), die selbst keinen Store kennen.
    var handlers: QuickEntryHandlers {
        QuickEntryHandlers(
            preview: { preview($0) },
            commit: { commit($0) },
            resolve: { resolve($0, $1) }
        )
    }

    func preview(_ text: String) -> QuickEntryPreview? {
        let now = Date.now
        switch store.quickEntry(text, now: now) {
        case .success(let quick):
            guard let projectId = quick.projectId else {
                return .error(QuickEntryError.missingProject.errorDescription ?? "")
            }
            let project = item(for: projectId)
            if quick.isRunningStart {
                // Wie `TaktStore.commit`: erst ab einer Minute Abstand rückwirkend.
                let since = quick.start < now.addingTimeInterval(-60) ? quick.start : nil
                return .start(project: project, since: since, tag: quick.tag, note: quick.note)
            }
            return .entry(project: project, day: Self.dayLabel(quick.start, now: now), start: quick.start,
                          end: quick.end ?? now, tag: quick.tag, note: quick.note)
        case .failure(.empty):
            return nil
        case .failure(.ambiguousProject(let projects)):
            return .ambiguous(message: "Mehrere Projekte passen:", candidates: projects.map(item))
        case .failure(let error):
            return .error(error.errorDescription ?? "Die Eingabe ist unvollständig.")
        }
    }

    /// Übernimmt die Eingabe; Erfolg liefert die Bestätigung samt Projektfarbe.
    func commit(_ text: String) -> Result<QuickEntrySuccess, QuickEntryFailure> {
        switch store.quickEntry(text, now: .now) {
        case .success(let quick):
            let preview = preview(text)
            guard store.commit(quick) else {
                return .failure(QuickEntryFailure(
                    message: store.consumeError() ?? "Die Eingabe konnte nicht übernommen werden."))
            }
            switch preview {
            case let .entry(project, day, start, end, _, _):
                let span = "\(TodayFormat.clock(start))–\(TodayFormat.clock(end))"
                return .success(QuickEntrySuccess(
                    message: "Eingetragen: \(project.name) · \([day, span].compactMap { $0 }.joined(separator: " "))",
                    colorHex: project.colorHex, isStart: false))
            case let .start(project, since, _, _):
                let message = since.map { "Gestartet: \(project.name) seit \(TodayFormat.clock($0))" }
                    ?? "Gestartet: \(project.name)"
                return .success(QuickEntrySuccess(message: message, colorHex: project.colorHex, isStart: true))
            default:
                return .success(QuickEntrySuccess(message: "Übernommen", colorHex: nil, isStart: false))
            }
        case .failure(let error):
            return .failure(QuickEntryFailure(message: error.errorDescription ?? "Die Eingabe ist unvollständig."))
        }
    }

    /// Ersetzt die mehrdeutigen Wörter (bis drei zusammenhängende) durch den vollen Projektnamen.
    func resolve(_ text: String, _ project: TodayData.ProjectItem) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        for length in 1...min(3, words.count) {
            for start in 0...(words.count - length) where !words[start].hasPrefix("#") {
                var candidate = words
                candidate.replaceSubrange(start..<(start + length), with: [project.name])
                let joined = candidate.joined(separator: " ")
                if case .success(let quick) = store.quickEntry(joined), quick.projectId == project.id {
                    return joined
                }
            }
        }
        return nil
    }

    // MARK: Interna

    private func item(_ project: Project) -> TodayData.ProjectItem {
        TodayData.ProjectItem(id: project.id, name: project.name, colorHex: project.colorHex,
                              isBusiness: project.isBusiness)
    }

    private func item(for projectId: UUID) -> TodayData.ProjectItem {
        if let project = store.project(id: projectId) { return item(project) }
        return TodayData.ProjectItem(id: projectId, name: "Unbekanntes Projekt", colorHex: "", isBusiness: false)
    }

    /// „gestern“, „vorgestern“, sonst „Mo 19.10.“; heute `nil`.
    static func dayLabel(_ date: Date, now: Date) -> String? {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days == 1 { return "gestern" }
        if days == 2 { return "vorgestern" }
        let weekdays = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
        let c = calendar.dateComponents([.weekday, .day, .month], from: date)
        return "\(weekdays[(c.weekday ?? 1) - 1]) \(c.day ?? 0).\(c.month ?? 0)."
    }
}
