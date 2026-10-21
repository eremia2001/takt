import Foundation
import SwiftUI
#if canImport(TaktCore)
import TaktCore
#endif

// Daten und Formate der Ansicht „Heute“. Ohne Store-Abhängigkeit: `TodayView` befüllt
// `TodayData` aus dem `TaktStore`, Vorschauen und das Render-Harness aus Beispieldaten.
// (Ohne TaktCore – z. B. im Harness – wird `DurationFormat` direkt mitkompiliert.)

struct TodayData {
    struct ProjectItem: Identifiable, Hashable {
        let id: UUID
        let name: String
        let colorHex: String
        let isBusiness: Bool

        var color: Color { Color(hex: colorHex) }
        /// Projektfarbe als Grund für weiße Schrift.
        var colorBehindWhite: Color { DesignColor.behindWhite(colorHex) }
        var kind: String { isBusiness ? "Business" : "Privat" }
    }

    struct EntryItem: Identifiable, Hashable {
        let id: UUID
        let project: ProjectItem
        let start: Date
        /// `nil` = läuft.
        let end: Date?
        let nextStep: String?
        /// Tag des Eintrags („Meeting“), `nil` = ohne.
        var tag: String? = nil

        var isRunning: Bool { end == nil }

        func duration(now: Date) -> TimeInterval {
            max(0, (end ?? now).timeIntervalSince(start))
        }
    }

    /// Projekt, mit dem es nach einer Pause weitergeht, samt dessen letztem „Nächsten Schritt“.
    struct Resume: Hashable {
        let project: ProjectItem
        let nextStep: String?
    }

    /// Kalendertermin für Tagesleiste und Terminliste (ohne EventKit, siehe `CalendarService`).
    struct EventItem: Identifiable, Hashable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let calendarTitle: String
        let calendarColor: Color
        var isAllDay = false
        /// Projekt der ersten passenden Kalender-Regel, sonst `nil`.
        var project: ProjectItem? = nil
        /// Schon als Eintrag erfasst (Eintrag mit gleichem Zeitraum ±1 min).
        var isCaptured = false

        /// Läuft der Termin gerade?
        func isCurrent(now: Date) -> Bool { start <= now && now < end }
    }

    /// Hinweis: Ein Termin läuft, der Timer aber auf einem anderen Projekt.
    struct MeetingHint: Hashable {
        let event: EventItem
        let runningProject: ProjectItem
        /// Projekt aus der Regel – nur dann gibt es „Wechseln zu …“.
        var target: ProjectItem? { event.project }
    }

    /// Geplanter „nächster Block“.
    struct PlannedItem: Hashable {
        let project: ProjectItem
        let startAt: Date
        let note: String?

        /// Beginn erreicht (oder vorbei).
        func isDue(now: Date) -> Bool { startAt <= now }
    }

    var now: Date
    /// Beginn des heutigen Tages (für Tagesleiste und Zuschnitt).
    var dayStart: Date
    /// Aktive Projekte in Sortierreihenfolge.
    var projects: [ProjectItem]
    /// Heutige Einträge, chronologisch aufsteigend (ein laufender Eintrag steht zuletzt).
    var entries: [EntryItem]
    /// Tagessumme inklusive laufendem Eintrag, auf heute zugeschnitten.
    var todayTotal: TimeInterval
    var switches: Int
    var longestBlock: TimeInterval
    /// Nur bei Pause: „Weiter mit …“.
    var resume: Resume?
    /// Nur wenn etwas läuft: „Nächster Schritt“ aus dem vorigen Lauf dieses Projekts.
    var runningNextStep: String?
    /// Geplanter nächster Block, falls vorhanden.
    var plannedBlock: PlannedItem? = nil
    /// Heute als frei markiert: Art („Urlaub“), sonst `nil`.
    var todayOff: String? = nil
    /// Heutige Termine mit Uhrzeit (Tagesleiste, Liste „Termine heute“), nach Beginn sortiert.
    /// Leer, wenn „Termine in Heute anzeigen“ aus ist oder der Kalenderzugriff fehlt.
    var events: [EventItem] = []
    /// Ganztägige Termine heute – nur als Hinweis, nicht in der Tagesleiste.
    var allDayEvents: [EventItem] = []

    /// Termin, der gerade läuft, während der Timer auf einem anderen Projekt steht: anderes
    /// Regel-Projekt, oder der Termin hat keine Regel (dann ohne „Wechseln“).
    var meetingHint: MeetingHint? {
        guard let running else { return nil }
        let current = events.filter { $0.isCurrent(now: now) && !$0.isCaptured }
        // Ohne Regel nur, wenn der laufende Eintrag nicht ohnehin als Meeting markiert ist.
        let tracksMeeting = running.tag?.compare("Meeting", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        guard let event = current.first(where: { $0.project != nil && $0.project?.id != running.project.id })
            ?? (tracksMeeting ? nil : current.first(where: { $0.project == nil })) else { return nil }
        return MeetingHint(event: event, runningProject: running.project)
    }

    var running: EntryItem? { entries.last(where: \.isRunning) }
    var lastCompleted: EntryItem? { entries.last(where: { !$0.isRunning }) }

    /// Pause seit dem letzten heutigen Stopp (nur wenn nichts läuft).
    var pauseSinceLastStop: (since: Date, duration: TimeInterval)? {
        guard running == nil, let end = lastCompleted?.end else { return nil }
        return (end, max(0, now.timeIntervalSince(end)))
    }

    // MARK: Tagesleiste

    /// Standardfenster der Tagesleiste in vollen Stunden.
    static let defaultWindow = 8...19

    /// Sichtbares Zeitfenster in vollen Stunden: 8–19 Uhr, erweitert um Einträge außerhalb.
    var dayWindow: ClosedRange<Int> {
        var lower = Self.defaultWindow.lowerBound
        var upper = Self.defaultWindow.upperBound
        for entry in entries {
            lower = min(lower, Int(hourOfDay(entry.start).rounded(.down)))
            upper = max(upper, Int(hourOfDay(entry.end ?? now).rounded(.up)))
        }
        for event in events {
            lower = min(lower, Int(hourOfDay(event.start).rounded(.down)))
            upper = max(upper, Int(hourOfDay(event.end).rounded(.up)))
        }
        lower = max(0, lower)
        upper = min(24, max(upper, lower + 1))
        return lower...upper
    }

    /// Stunde (0…24, gebrochen) eines Zeitpunkts im heutigen Tag; außerhalb wird begrenzt.
    func hourOfDay(_ date: Date) -> Double {
        if date <= dayStart { return 0 }
        let calendar = Calendar.current
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart), date < dayEnd else { return 24 }
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60 + Double(parts.second ?? 0) / 3600
    }
}

// MARK: - Schnelleingabe

/// Vorschau einer Schnelleingabe, ohne TaktCore-Abhängigkeit (`TodayView` übersetzt das
/// Ergebnis von `QuickEntryParser`).
enum QuickEntryPreview: Hashable {
    /// Fertiger Eintrag: Projekt, Tag (nur wenn nicht heute, z. B. „gestern“), Spanne, Dauer.
    case entry(project: TodayData.ProjectItem, day: String?, start: Date, end: Date, tag: String?, note: String?)
    /// Timer-Start; `since` gesetzt, wenn er rückwirkend beginnt.
    case start(project: TodayData.ProjectItem, since: Date?, tag: String?, note: String?)
    /// Mehrere Projekte passen gleich gut – Auswahl per Klick.
    case ambiguous(message: String, candidates: [TodayData.ProjectItem])
    case error(String)

    var isValid: Bool {
        switch self {
        case .entry, .start: true
        case .ambiguous, .error: false
        }
    }
}

/// Aktionen der Ansicht; `TodayView` verdrahtet sie mit dem Store.
struct TodayActions {
    var start: (TodayData.ProjectItem) -> Void = { _ in }
    /// Stoppt mit optionalem „Nächsten Schritt“ und dem Tag des laufenden Eintrags
    /// (leer = ohne Tag).
    var stop: (_ nextStep: String, _ tag: String) -> Void = { _, _ in }
    /// Tag-Vorschläge für ein Projekt und einen Anfang (leer = zuletzt genutzte).
    var tagSuggestions: (_ projectId: UUID?, _ prefix: String) -> [String] = { _, _ in [] }
    /// Live-Vorschau der Schnelleingabe; `nil` bei leerem Text.
    var previewQuickEntry: (String) -> QuickEntryPreview? = { _ in nil }
    /// Übernimmt die Schnelleingabe. Ergebnis: Bestätigung bei Erfolg, sonst Fehlertext.
    var commitQuickEntry: (String) -> Result<String, QuickEntryFailure> = { _ in .failure(QuickEntryFailure(message: "")) }
    /// Ersetzt im Text das mehrdeutige Projekt durch das gewählte; `nil`, wenn das nicht gelingt.
    var resolveQuickEntry: (_ text: String, _ project: TodayData.ProjectItem) -> String? = { _, _ in nil }
    /// Öffnet „Freie Tage“ für heute.
    var markTodayOff: () -> Void = {}
    var openEntry: (TodayData.EntryItem) -> Void = { _ in }
    var deleteEntry: (TodayData.EntryItem) -> Void = { _ in }
    var addEntry: () -> Void = {}
    var showProjects: () -> Void = {}
    /// Neues Projekt anlegen (öffnet den Projekt-Editor) – für den leeren Zustand ohne Projekte.
    var createProject: () -> Void = {}
    /// Startet das Projekt des geplanten Blocks jetzt (der Block ist damit erledigt).
    var startPlannedBlock: () -> Void = {}
    var clearPlannedBlock: () -> Void = {}
    /// Plant den nächsten Block: Projekt, Beginn, Notiz (leer = keine).
    var planBlock: (UUID, Date, String) -> Void = { _, _, _ in }
    /// Termin als Eintrag übernehmen (öffnet den Editor vorbelegt).
    var captureEvent: (TodayData.EventItem) -> Void = { _ in }
}

/// Fehler beim Übernehmen einer Schnelleingabe (Text für die Vorschauzeile).
struct QuickEntryFailure: Error, Hashable {
    let message: String
}

// MARK: - Formate

enum TodayFormat {
    /// `h:mm`, abgerundet.
    static func duration(_ interval: TimeInterval) -> String {
        DurationFormat.hourMinute(interval)
    }

    static func clock(_ date: Date) -> String {
        ClockFormat.time(date)
    }

    /// Uhrzeit eines geplanten Blocks; nicht heute: mit „morgen“ bzw. Datum davor.
    static func plannedTime(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return clock(date) }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "morgen \(clock(date))"
        }
        return "\(date.formatted(.dateTime.day().month(.twoDigits).locale(Locale(identifier: "de_DE")))) \(clock(date))"
    }

    static func range(_ entry: TodayData.EntryItem) -> String {
        "\(clock(entry.start)) – \(entry.end.map(clock) ?? "jetzt")"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE, d. MMMM"
        return formatter
    }()

    /// „Dienstag, 20. Oktober“.
    static func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }
}

// MARK: - Beispieldaten (Vorschauen, Render-Harness)

#if DEBUG
extension TodayData {
    static let samplePortal = ProjectItem(id: UUID(), name: "Kundenportal", colorHex: "#3A7BD5", isBusiness: true)
    static let sampleWebsite = ProjectItem(id: UUID(), name: "Website", colorHex: "#30B0C7", isBusiness: true)
    static let sampleGarden = ProjectItem(id: UUID(), name: "Garten", colorHex: "#34C759", isBusiness: false)
    static let sampleTax = ProjectItem(id: UUID(), name: "Steuer", colorHex: "#FF9500", isBusiness: false)

    private static func sampleTime(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: hour, minute: minute))!
    }

    private static var sampleMorning: [EntryItem] {
        [
            EntryItem(id: UUID(), project: sampleWebsite, start: sampleTime(9, 5), end: sampleTime(10, 40),
                      nextStep: "Deploy-Skript fertig machen", tag: "Bugfix"),
            EntryItem(id: UUID(), project: samplePortal, start: sampleTime(10, 50), end: sampleTime(12, 20), nextStep: nil,
                      tag: "Meeting"),
            EntryItem(id: UUID(), project: sampleTax, start: sampleTime(13, 0), end: sampleTime(13, 35), nextStep: nil),
        ]
    }

    private static func sample(now: Date, entries: [EntryItem], resume: Resume?) -> TodayData {
        let total = entries.reduce(0) { $0 + $1.duration(now: now) }
        let switches = zip(entries, entries.dropFirst()).filter { $0.project.id != $1.project.id }.count
        return TodayData(
            now: now,
            dayStart: Calendar.current.startOfDay(for: now),
            projects: [samplePortal, sampleWebsite, sampleGarden, sampleTax],
            entries: entries,
            todayTotal: total,
            switches: switches,
            longestBlock: entries.map { $0.duration(now: now) }.max() ?? 0,
            resume: resume,
            runningNextStep: nil
        )
    }

    /// Läuft: Kundenportal seit 14:32, jetzt 15:56 → 1:24; Tag 5:04.
    static var sampleRunning: TodayData {
        sample(
            now: sampleTime(15, 56),
            entries: sampleMorning + [
                EntryItem(id: UUID(), project: samplePortal, start: sampleTime(14, 32), end: nil, nextStep: nil,
                          tag: "Review"),
            ],
            resume: nil
        )
    }

    /// Pause: Kundenportal um 15:56 gestoppt (mit Notiz), jetzt 16:10.
    static var sampleIdle: TodayData {
        let step = "Login-Fehler im Staging nachstellen"
        return sample(
            now: sampleTime(16, 10),
            entries: sampleMorning + [
                EntryItem(id: UUID(), project: samplePortal, start: sampleTime(14, 32), end: sampleTime(15, 56),
                          nextStep: step),
            ],
            resume: Resume(project: samplePortal, nextStep: step)
        ).withPlannedBlock(PlannedItem(project: sampleWebsite, startAt: sampleTime(16, 30), note: "Deploy vorbereiten"))
    }

    /// Läuft (Website seit 14:32, jetzt 15:56) mit Terminen: „Review Gerlach“ läuft gerade und
    /// gehört per Regel zum Kundenportal; „Standup“ ist schon erfasst; ein ganztägiger Feiertag.
    static var sampleWithEvents: TodayData {
        let blue = Color(hex: "#3A7BD5")
        let purple = Color(hex: "#AF52DE")
        let standupStart = sampleTime(9, 30)
        var data = sample(
            now: sampleTime(15, 56),
            entries: [
                EntryItem(id: UUID(), project: samplePortal, start: standupStart, end: sampleTime(9, 45),
                          nextStep: "Standup", tag: "Meeting"),
                EntryItem(id: UUID(), project: sampleWebsite, start: sampleTime(9, 50), end: sampleTime(12, 10),
                          nextStep: "Deploy-Skript fertig machen", tag: "Bugfix"),
                EntryItem(id: UUID(), project: sampleTax, start: sampleTime(13, 0), end: sampleTime(13, 35), nextStep: nil),
                EntryItem(id: UUID(), project: sampleWebsite, start: sampleTime(14, 32), end: nil, nextStep: nil),
            ],
            resume: nil
        )
        data.events = [
            EventItem(id: "standup", title: "Standup", start: standupStart, end: sampleTime(9, 45),
                      calendarTitle: "Arbeit", calendarColor: blue, project: samplePortal, isCaptured: true),
            EventItem(id: "lunch", title: "Mittag mit Jana", start: sampleTime(12, 15), end: sampleTime(13, 0),
                      calendarTitle: "Privat", calendarColor: purple),
            EventItem(id: "review", title: "Review Gerlach", start: sampleTime(15, 30), end: sampleTime(16, 30),
                      calendarTitle: "Arbeit", calendarColor: blue, project: samplePortal),
            EventItem(id: "call", title: "Telefonat Steuerberater", start: sampleTime(17, 0), end: sampleTime(17, 30),
                      calendarTitle: "Privat", calendarColor: purple, project: sampleTax),
        ]
        data.allDayEvents = [
            EventItem(id: "holiday", title: "Tag der offenen Tür", start: sampleTime(0, 0), end: sampleTime(23, 59),
                      calendarTitle: "Arbeit", calendarColor: blue, isAllDay: true),
        ]
        return data
    }

    private func withPlannedBlock(_ block: PlannedItem) -> TodayData {
        var copy = self
        copy.plannedBlock = block
        return copy
    }
}
#endif
