import EventKit
import SwiftUI

/// Ein Kalendertermin, wie „Heute“ ihn braucht – ohne EventKit-Objekte, damit Ansichten und
/// Vergleiche nichts vom `EKEventStore` festhalten.
struct CalendarEventInfo: Identifiable, Hashable {
    /// Eindeutig je Vorkommen: Wiederholungen teilen sich `eventIdentifier`, daher mit Beginn.
    let id: String
    let title: String
    let start: Date
    let end: Date
    let calendarTitle: String
    let calendarColor: Color
    let isAllDay: Bool
    /// Domains der Teilnehmer und des Organisators („acme.de“), klein, ohne Dubletten.
    let attendeeDomains: [String]

    init(event: EKEvent) {
        let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
        id = "\(identifier)|\(event.startDate.timeIntervalSinceReferenceDate)"
        let trimmed = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        title = trimmed.isEmpty ? "Ohne Titel" : trimmed
        start = event.startDate
        end = max(event.endDate, event.startDate)
        calendarTitle = event.calendar?.title ?? ""
        calendarColor = event.calendar?.cgColor.map { Color(cgColor: $0) } ?? .gray
        isAllDay = event.isAllDay
        var participants = event.attendees ?? []
        if let organizer = event.organizer { participants.append(organizer) }
        var domains: [String] = []
        for participant in participants {
            guard let domain = Self.domain(of: participant.url), !domains.contains(domain) else { continue }
            domains.append(domain)
        }
        attendeeDomains = domains
    }

    /// Domain aus einer Teilnehmer-URL (`mailto:anna@acme.de`); ohne Adresse `nil`.
    private static func domain(of url: URL) -> String? {
        let text = (url as NSURL).resourceSpecifier ?? url.absoluteString
        guard let at = text.lastIndex(of: "@") else { return nil }
        let domain = text[text.index(after: at)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return domain.isEmpty ? nil : domain
    }
}

/// Eine Quelle, in der Takt seinen Kalender anlegen kann (iCloud, Google, Exchange, lokal).
struct CalendarSourceInfo: Identifiable, Hashable {
    let id: String
    let title: String
    /// Art für die Anzeige: „iCloud“, „Google“, „Exchange“, „Auf meinem Mac“, „CalDAV“.
    let kind: String

    init(source: EKSource) {
        id = source.sourceIdentifier
        title = source.title
        kind = Self.kind(of: source)
    }

    /// Anzeigename im Picker, z. B. „iCloud“ oder „Google · anna@gmail.com“.
    var label: String {
        if title.caseInsensitiveCompare(kind) == .orderedSame || title.isEmpty { return kind }
        return "\(kind) · \(title)"
    }

    private static func kind(of source: EKSource) -> String {
        let title = source.title.lowercased()
        switch source.sourceType {
        case .local: return "Auf meinem Mac"
        case .exchange: return "Exchange"
        case .mobileMe: return "iCloud"
        case .calDAV:
            if title.contains("icloud") { return "iCloud" }
            if title.contains("google") || title.contains("gmail") { return "Google" }
            return "CalDAV"
        default: return source.title
        }
    }
}
