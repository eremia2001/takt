import AppKit
import EventKit
import Foundation
import Observation
import OSLog
import TaktCore

/// Kalender-Anbindung über EventKit: Berechtigung, Termine für „Heute“ und die Spiegelung
/// erfasster Zeiten in einen eigenen Kalender „Takt“.
///
/// Grundsätze:
/// - Gelesen wird aus allen (bzw. den gewählten) Ereigniskalendern, geschrieben **nur** in den
///   Spiegel-Kalender (`AppSettings.calendarMirrorCalendarID`). Ereignisse anderer Kalender werden
///   nie verändert.
/// - Eigene Ereignisse tragen die URL `takt://entry/<UUID>` – darüber erkennt der Abgleich sie
///   wieder, auch wenn die Verknüpfung in der Datenbank fehlt.
/// - Die Farbe kommt vom Kalender; ein Kalender je Projekt ist nicht nötig.
@MainActor
@Observable
final class CalendarService {
    // MARK: Konstanten

    /// Name des Spiegel-Kalenders.
    static let mirrorCalendarTitle = "Takt"
    /// Gespiegelt werden Einträge, die in diesem Zeitraum enden.
    static let mirrorWindow: TimeInterval = 30 * 24 * 3600
    /// Bündelung: so lange nach der letzten Änderung wird gespiegelt.
    static let mirrorDelay: Duration = .seconds(5)
    /// Vollständiger Abgleich (gelöschte/verkürzte Einträge, im Kalender gelöschte Ereignisse)
    /// höchstens so oft – außer beim Start und bei „Jetzt spiegeln“.
    static let fullReconcileInterval: TimeInterval = 30 * 60
    /// Präfix der Ereignis-URL eigener Ereignisse.
    static let entryURLPrefix = "takt://entry/"

    // MARK: Zustand

    private(set) var authorizationStatus: EKAuthorizationStatus
    /// Alle Ereigniskalender, nach Quelle und Name sortiert (leer ohne Vollzugriff).
    private(set) var calendars: [EKCalendar] = []
    /// Quellen, in denen Takt seinen Kalender anlegen kann.
    private(set) var mirrorSources: [CalendarSourceInfo] = []
    /// Ereignisse von Takt im Spiegel-Kalender (letzte drei Jahre).
    private(set) var mirroredCount = 0
    /// Zeitpunkt der letzten erfolgreichen Spiegelung.
    private(set) var lastMirrorAt: Date?
    /// Letzte Fehlermeldung für die Einstellungen.
    var lastError: String?
    /// Zählt Änderungen im Kalender und Tageswechsel – Ansichten, die `events(on:)` lesen,
    /// zeichnen darüber neu.
    private(set) var revision = 0

    var hasFullAccess: Bool { authorizationStatus == .fullAccess }
    /// Die Systemabfrage ist noch möglich (sonst nur über die Systemeinstellungen).
    var canRequestAccess: Bool { authorizationStatus == .notDetermined }

    // MARK: Interna

    @ObservationIgnored private var eventStore = EKEventStore()
    @ObservationIgnored private let store: TaktStore
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private var mirrorTask: Task<Void, Never>?
    @ObservationIgnored private var pendingFullReconcile = true
    @ObservationIgnored private var lastFullReconcile: Date?
    @ObservationIgnored private var periodicTimer: Timer?
    @ObservationIgnored private var dayCache: (key: String, events: [CalendarEventInfo])?

    private static let logger = Logger(subsystem: "dev.eremiya.takt", category: "calendar")

    init(store: TaktStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        // Ohne Zugriff bleiben Termine aus, auch wenn der Schalter noch an ist.
        if hasFullAccess { reloadCalendars() }
        startObserving()
        // Spiegelung: nach jedem Stopp/Bearbeiten (Store neu geladen) gebündelt, und beim Start.
        observeContinuously { [weak self] in
            guard let self else { return }
            _ = self.store.todayEntries
            _ = self.store.running?.entry.id
            _ = self.settings.calendarMirrorEnabled
            _ = self.settings.calendarMirrorMinimumMinutes
            _ = self.settings.calendarMirrorCalendarID
            self.scheduleMirror()
        }
    }

    // MARK: Berechtigung

    /// Fragt nach Vollzugriff (macOS 14+). Bei Erfolg werden Termine in „Heute“ eingeschaltet.
    func requestAccess() async {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            Self.logger.info("Kalenderzugriff: \(granted ? "erteilt" : "abgelehnt", privacy: .public)")
        } catch {
            Self.logger.error("Kalenderzugriff fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            lastError = "Zugriff auf Kalender nicht möglich: \(error.localizedDescription)"
        }
        let wasFull = hasFullAccess
        updateAuthorizationStatus()
        if hasFullAccess, !wasFull {
            settings.calendarShowEvents = true
        }
    }

    /// Öffnet Systemeinstellungen › Datenschutz › Kalender (nach einer Ablehnung).
    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Kurzer Statustext für die Einstellungen.
    var statusText: String {
        switch authorizationStatus {
        case .fullAccess: "Zugriff erlaubt"
        case .notDetermined: "Noch nicht erlaubt"
        case .denied: "Zugriff abgelehnt – in den Systemeinstellungen freigeben"
        case .restricted: "Zugriff durch das System eingeschränkt"
        case .writeOnly: "Nur Schreibzugriff – für Termine wird voller Zugriff gebraucht"
        @unknown default: "Unbekannter Status"
        }
    }

    // MARK: Termine

    /// Termine eines Tages aus den sichtbaren Kalendern (`calendarVisibleIDs`, leer = alle außer
    /// dem Spiegel-Kalender), nach Beginn sortiert. Ganztägige sind enthalten (`isAllDay`); die
    /// Tagesleiste blendet sie aus und zeigt sie als Hinweis.
    func events(on day: Date) -> [CalendarEventInfo] {
        // Für die Beobachtung lesen: Ansichten zeichnen bei Änderungen neu.
        let revision = revision
        let visible = settings.calendarVisibleIDs
        let mirrorID = settings.calendarMirrorCalendarID
        guard hasFullAccess else { return [] }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let key = "\(start.timeIntervalSinceReferenceDate)|\(revision)|\(visible.joined(separator: ","))|\(mirrorID ?? "")"
        if let dayCache, dayCache.key == key { return dayCache.events }

        let sources = visibleCalendars
        var result: [CalendarEventInfo] = []
        if !sources.isEmpty {
            let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: sources)
            result = eventStore.events(matching: predicate)
                .filter { $0.status != .canceled }
                .map(CalendarEventInfo.init(event:))
                .sorted { ($0.start, $0.end, $0.title) < ($1.start, $1.end, $1.title) }
        }
        dayCache = (key, result)
        return result
    }

    /// Kalender, deren Termine in „Heute“ erscheinen. Der Spiegel-Kalender nie – er enthält die
    /// Einträge selbst.
    var visibleCalendars: [EKCalendar] {
        let ids = Set(settings.calendarVisibleIDs)
        return calendars.filter { calendar in
            guard !isMirrorCalendar(calendar) else { return false }
            return ids.isEmpty || ids.contains(calendar.calendarIdentifier)
        }
    }

    func isVisible(_ calendar: EKCalendar) -> Bool {
        visibleCalendars.contains { $0.calendarIdentifier == calendar.calendarIdentifier }
    }

    /// Blendet einen Kalender in „Heute“ ein oder aus. Sind wieder alle an, gilt „leer = alle“
    /// (dann erscheinen auch neu hinzukommende Kalender).
    func setVisible(_ visible: Bool, calendar: EKCalendar) {
        let selectable = calendars.filter { !isMirrorCalendar($0) }.map(\.calendarIdentifier)
        var ids = Set(settings.calendarVisibleIDs.isEmpty ? selectable : settings.calendarVisibleIDs)
        if visible { ids.insert(calendar.calendarIdentifier) } else { ids.remove(calendar.calendarIdentifier) }
        let ordered = selectable.filter { ids.contains($0) }
        settings.calendarVisibleIDs = ordered.count == selectable.count ? [] : ordered
    }

    /// Ist das der (oder ein) Takt-Kalender? Ohne gewählten Spiegel-Kalender zählt der Name.
    func isMirrorCalendar(_ calendar: EKCalendar) -> Bool {
        if let id = settings.calendarMirrorCalendarID { return calendar.calendarIdentifier == id }
        return calendar.title == Self.mirrorCalendarTitle && calendar.allowsContentModifications
    }

    // MARK: Spiegel-Kalender

    /// Der gewählte Spiegel-Kalender, sofern vorhanden und beschreibbar.
    var mirrorCalendar: EKCalendar? {
        guard hasFullAccess, let id = settings.calendarMirrorCalendarID,
              let calendar = eventStore.calendar(withIdentifier: id),
              calendar.allowsContentModifications else { return nil }
        return calendar
    }

    /// Quelle des Spiegel-Kalenders.
    var mirrorSourceID: String? {
        mirrorCalendar?.source?.sourceIdentifier
    }

    /// Schaltet die Spiegelung ein: legt den Kalender „Takt“ in der Quelle an (oder nutzt einen
    /// vorhandenen dieses Namens) und spiegelt sofort.
    @discardableResult
    func enableMirror(sourceID: String? = nil) -> Bool {
        guard hasFullAccess else {
            lastError = "Ohne Kalenderzugriff kann Takt nicht spiegeln."
            return false
        }
        if mirrorCalendar == nil || (sourceID != nil && sourceID != mirrorSourceID) {
            guard let source = sourceID ?? defaultMirrorSourceID else {
                lastError = "Keine Kalenderquelle gefunden, in der Takt einen Kalender anlegen kann."
                return false
            }
            guard useMirrorSource(source) else { return false }
        }
        settings.calendarMirrorEnabled = true
        mirrorNow()
        return true
    }

    /// Wechselt die Quelle des Spiegel-Kalenders. Bisher gespiegelte Ereignisse bleiben im alten
    /// Kalender; die Einträge der letzten 30 Tage landen beim nächsten Abgleich im neuen.
    @discardableResult
    func useMirrorSource(_ sourceID: String) -> Bool {
        guard let source = eventStore.sources.first(where: { $0.sourceIdentifier == sourceID }) else {
            lastError = "Die gewählte Kalenderquelle gibt es nicht mehr."
            return false
        }
        let existing = source.calendars(for: .event).first {
            $0.title == Self.mirrorCalendarTitle && $0.allowsContentModifications
        }
        let target: EKCalendar
        if let existing {
            target = existing
        } else {
            let calendar = EKCalendar(for: .event, eventStore: eventStore)
            calendar.title = Self.mirrorCalendarTitle
            calendar.source = source
            calendar.cgColor = NSColor(srgbRed: 0x3A / 255, green: 0x7B / 255, blue: 0xD5 / 255, alpha: 1).cgColor
            do {
                try eventStore.saveCalendar(calendar, commit: true)
                Self.logger.info("Kalender „Takt“ angelegt in \(source.title, privacy: .public)")
            } catch {
                Self.logger.error("Kalender anlegen fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
                let kind = CalendarSourceInfo(source: source).kind
                lastError = "In „\(kind)“ kann Takt keinen Kalender anlegen (\(error.localizedDescription)). "
                    + "Lege dort selbst einen Kalender „Takt“ an und wähle die Quelle erneut."
                return false
            }
            target = calendar
        }
        settings.calendarMirrorCalendarID = target.calendarIdentifier
        lastError = nil
        reloadCalendars()
        if settings.calendarMirrorEnabled { mirrorNow() }
        return true
    }

    /// Vorschlag für die Quelle: die des Standardkalenders, sonst iCloud, sonst die erste.
    private var defaultMirrorSourceID: String? {
        let ids = Set(mirrorSources.map(\.id))
        if let id = eventStore.defaultCalendarForNewEvents?.source?.sourceIdentifier, ids.contains(id) { return id }
        return mirrorSources.first?.id
    }

    /// Schaltet die Spiegelung aus; auf Wunsch werden die Ereignisse von Takt im Spiegel-Kalender
    /// gelöscht (nur solche mit `takt://entry/…`-URL) und die Verknüpfungen entfernt.
    func disableMirror(deleteEvents: Bool) {
        settings.calendarMirrorEnabled = false
        mirrorTask?.cancel()
        guard deleteEvents, let target = mirrorCalendar else { return }
        let now = Date.now
        // EventKit liefert höchstens vier Jahre je Abfrage.
        let predicate = eventStore.predicateForEvents(
            withStart: now.addingTimeInterval(-3 * 365 * 24 * 3600),
            end: now.addingTimeInterval(24 * 3600),
            calendars: [target]
        )
        var removed: [UUID] = []
        for event in eventStore.events(matching: predicate) {
            guard let entryId = Self.entryId(from: event.url) else { continue }
            do {
                try eventStore.remove(event, span: .thisEvent, commit: false)
                removed.append(entryId)
            } catch {
                Self.logger.error("Ereignis löschen fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            }
        }
        do {
            try eventStore.commit()
        } catch {
            eventStore.reset()
            lastError = "Ereignisse konnten nicht gelöscht werden: \(error.localizedDescription)"
            return
        }
        for entryId in removed { store.removeCalendarLink(entryId: entryId) }
        Self.logger.info("Spiegelung aus, \(removed.count) Ereignisse gelöscht")
        updateMirroredCount()
    }

    // MARK: Spiegelung

    /// Spiegelt sofort mit vollständigem Abgleich („Jetzt spiegeln“).
    func mirrorNow() {
        mirrorTask?.cancel()
        mirrorTask = nil
        runMirror(full: true)
    }

    /// Plant eine Spiegelung in `mirrorDelay`; weitere Aufrufe davor verschieben sie (bündeln).
    func scheduleMirror(full: Bool = false) {
        if full { pendingFullReconcile = true }
        mirrorTask?.cancel()
        mirrorTask = Task { [weak self] in
            try? await Task.sleep(for: Self.mirrorDelay)
            guard !Task.isCancelled, let self else { return }
            self.mirrorTask = nil
            self.runMirror(full: false)
        }
    }

    private func runMirror(full: Bool) {
        guard settings.calendarMirrorEnabled, hasFullAccess else { return }
        guard mirrorCalendar != nil else {
            // Kalender in der Kalender-App gelöscht oder Konto entfernt.
            lastError = "Der Kalender „Takt“ fehlt. Wähle die Quelle neu, um ihn wieder anzulegen."
            return
        }
        let due = lastFullReconcile.map { Date.now.timeIntervalSince($0) > Self.fullReconcileInterval } ?? true
        if full || pendingFullReconcile || due {
            pendingFullReconcile = false
            reconcile()
            lastFullReconcile = .now
        }
        mirrorPendingEntries()
        updateMirroredCount()
    }

    /// Legt für jeden Eintrag, der (neu) gespiegelt werden muss, ein Ereignis an bzw. aktualisiert
    /// es und merkt sich die Verknüpfung. Gibt die Zahl gespiegelter Einträge zurück.
    @discardableResult
    func mirrorPendingEntries() -> Int {
        guard settings.calendarMirrorEnabled, hasFullAccess, let target = mirrorCalendar else { return 0 }
        let since = Date.now.addingTimeInterval(-Self.mirrorWindow)
        let minimum = TimeInterval(settings.calendarMirrorMinimumMinutes * 60)
        let pending = store.entriesNeedingMirror(since: since, minimumDuration: minimum)
        guard !pending.isEmpty else { return 0 }

        var saved: [(entryId: UUID, event: EKEvent)] = []
        for entry in pending {
            guard let end = entry.endedAt else { continue }
            let event = linkedEvent(entryId: entry.id, in: target) ?? {
                let event = EKEvent(eventStore: eventStore)
                event.calendar = target
                return event
            }()
            event.title = Self.eventTitle(projectName: store.project(id: entry.projectId)?.name, tag: entry.tag)
            event.notes = entry.nextStep
            event.isAllDay = false
            event.startDate = entry.startedAt
            event.endDate = end
            event.url = URL(string: Self.entryURLPrefix + entry.id.uuidString)
            do {
                try eventStore.save(event, span: .thisEvent, commit: false)
                saved.append((entry.id, event))
            } catch {
                Self.logger.error("Spiegeln fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
                lastError = "Spiegeln fehlgeschlagen: \(error.localizedDescription)"
            }
        }
        guard !saved.isEmpty else { return 0 }
        do {
            try eventStore.commit()
        } catch {
            eventStore.reset()
            Self.logger.error("Spiegeln (Commit) fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            lastError = "Spiegeln fehlgeschlagen: \(error.localizedDescription)"
            return 0
        }

        let now = Date.now
        var linked = 0
        for item in saved {
            guard let identifier = item.event.eventIdentifier else { continue }
            let link = CalendarEventLink(
                entryId: item.entryId, eventIdentifier: identifier,
                calendarIdentifier: target.calendarIdentifier, updatedAt: now
            )
            if store.setCalendarLink(link) { linked += 1 }
        }
        lastMirrorAt = now
        Self.logger.info("\(linked) Einträge gespiegelt")
        return linked
    }

    /// Vollständiger Abgleich im Spiegel-Zeitraum:
    /// 1. verwaiste Verknüpfungen (laufende/fehlende Einträge) entfernen, deren Ereignisse löschen;
    /// 2. eigene Ereignisse ohne passenden Eintrag (gelöscht, wieder laufend, zu kurz, Dublette)
    ///    löschen – Ereignisse ohne Verknüpfung werden übernommen statt doppelt angelegt;
    /// 3. Verknüpfungen, deren Ereignis fehlt (im Kalender gelöscht) oder in einem anderen
    ///    Kalender liegt (Quelle gewechselt), lösen, damit neu gespiegelt wird.
    private func reconcile() {
        guard let target = mirrorCalendar else { return }

        for link in store.removeOrphanCalendarLinks() {
            removeOwnedEvent(link, commit: false)
        }
        commitOrReset()

        let now = Date.now
        let window = DateInterval(
            start: now.addingTimeInterval(-Self.mirrorWindow - 24 * 3600),
            end: now.addingTimeInterval(24 * 3600)
        )
        // Lesefehler dürfen nicht als „alle Einträge gelöscht“ gelten.
        let errorBefore = store.lastError
        let entries = store.entries(in: window)
        guard store.lastError == errorBefore else {
            Self.logger.error("Abgleich abgebrochen: Einträge nicht lesbar")
            commitOrReset()
            return
        }
        let byId = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let minimum = TimeInterval(settings.calendarMirrorMinimumMinutes * 60)

        var unlink: Set<UUID> = []
        var adopt: [UUID: String] = [:]
        var removedEvents = 0
        let predicate = eventStore.predicateForEvents(withStart: window.start, end: window.end, calendars: [target])
        for event in eventStore.events(matching: predicate) {
            guard let entryId = Self.entryId(from: event.url) else { continue }
            let link = store.calendarLink(entryId: entryId)
            var remove = false
            if let entry = byId[entryId] {
                let tooShort = entry.endedAt.map { $0.timeIntervalSince(entry.startedAt) < minimum } ?? true
                if tooShort {
                    remove = true
                    if link != nil { unlink.insert(entryId) }
                } else if let link, link.eventIdentifier != event.eventIdentifier {
                    // Dublette – außer das verknüpfte Ereignis gibt es nicht mehr.
                    if eventStore.event(withIdentifier: link.eventIdentifier) != nil {
                        remove = true
                    } else if let identifier = event.eventIdentifier {
                        adopt[entryId] = identifier
                    }
                } else if link == nil, let identifier = event.eventIdentifier, adopt[entryId] == nil {
                    adopt[entryId] = identifier
                } else if link == nil {
                    remove = true
                }
            } else if link == nil {
                // Eintrag gelöscht (die Verknüpfung ist per CASCADE mit verschwunden).
                remove = true
            }
            if remove {
                do {
                    try eventStore.remove(event, span: .thisEvent, commit: false)
                    removedEvents += 1
                } catch {
                    Self.logger.error("Ereignis löschen fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        commitOrReset()

        // Übernommene Ereignisse: Verknüpfung mit altem Stand, damit der Inhalt neu geschrieben wird.
        for (entryId, identifier) in adopt {
            store.setCalendarLink(CalendarEventLink(
                entryId: entryId, eventIdentifier: identifier,
                calendarIdentifier: target.calendarIdentifier, updatedAt: .distantPast
            ))
        }
        for entryId in unlink { store.removeCalendarLink(entryId: entryId) }

        // Verknüpfungen ohne Ereignis im Spiegel-Kalender lösen.
        let since = now.addingTimeInterval(-Self.mirrorWindow)
        var relinked = 0
        for entry in entries where adopt[entry.id] == nil && !unlink.contains(entry.id) {
            guard let end = entry.endedAt, end >= since, end.timeIntervalSince(entry.startedAt) >= minimum,
                  let link = store.calendarLink(entryId: entry.id) else { continue }
            let event = eventStore.event(withIdentifier: link.eventIdentifier)
            if link.calendarIdentifier != target.calendarIdentifier
                || event?.calendar?.calendarIdentifier != target.calendarIdentifier {
                store.removeCalendarLink(entryId: entry.id)
                relinked += 1
            }
        }
        if removedEvents + adopt.count + unlink.count + relinked > 0 {
            Self.logger.info("Abgleich: \(removedEvents) gelöscht, \(adopt.count) übernommen, \(unlink.count + relinked) neu zu spiegeln")
        }
    }

    /// Vor dem Löschen eines Eintrags aufrufen: entfernt sein gespiegeltes Ereignis. Danach löscht
    /// die Datenbank die Verknüpfung per CASCADE mit.
    func willDelete(entryId: UUID) {
        guard hasFullAccess, let link = store.calendarLink(entryId: entryId) else { return }
        removeOwnedEvent(link, commit: true)
        updateMirroredCount()
    }

    /// Löscht das Ereignis einer Verknüpfung – nur, wenn es im verknüpften Takt-Kalender liegt.
    private func removeOwnedEvent(_ link: CalendarEventLink, commit: Bool) {
        guard let event = eventStore.event(withIdentifier: link.eventIdentifier),
              let calendar = event.calendar,
              calendar.calendarIdentifier == link.calendarIdentifier,
              calendar.allowsContentModifications,
              calendar.calendarIdentifier == settings.calendarMirrorCalendarID
                || calendar.title == Self.mirrorCalendarTitle else { return }
        // Trägt das Ereignis eine Takt-URL, muss sie zum Eintrag passen.
        if let owner = Self.entryId(from: event.url), owner != link.entryId { return }
        do {
            try eventStore.remove(event, span: .thisEvent, commit: commit)
            Self.logger.info("Gespiegeltes Ereignis entfernt")
        } catch {
            Self.logger.error("Ereignis löschen fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func commitOrReset() {
        do {
            try eventStore.commit()
        } catch {
            eventStore.reset()
            Self.logger.error("Commit fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Das verknüpfte Ereignis eines Eintrags, sofern es im Zielkalender liegt.
    private func linkedEvent(entryId: UUID, in target: EKCalendar) -> EKEvent? {
        guard let link = store.calendarLink(entryId: entryId),
              link.calendarIdentifier == target.calendarIdentifier,
              let event = eventStore.event(withIdentifier: link.eventIdentifier),
              event.calendar?.calendarIdentifier == target.calendarIdentifier else { return nil }
        return event
    }

    private func updateMirroredCount() {
        guard let target = mirrorCalendar else {
            if mirroredCount != 0 { mirroredCount = 0 }
            return
        }
        let now = Date.now
        let predicate = eventStore.predicateForEvents(
            withStart: now.addingTimeInterval(-3 * 365 * 24 * 3600),
            end: now.addingTimeInterval(24 * 3600),
            calendars: [target]
        )
        let count = eventStore.events(matching: predicate).filter { Self.entryId(from: $0.url) != nil }.count
        if mirroredCount != count { mirroredCount = count }
    }

    // MARK: Hilfen

    /// „Projektname“, mit Tag „Projektname · #Tag“.
    static func eventTitle(projectName: String?, tag: String?) -> String {
        let name = projectName ?? "Takt"
        guard let tag = TimeEntry.normalizedTag(tag) else { return name }
        return "\(name) · #\(tag)"
    }

    /// Eintrags-ID aus `takt://entry/<UUID>`; fremde URLs → `nil`.
    static func entryId(from url: URL?) -> UUID? {
        guard let text = url?.absoluteString, text.hasPrefix(entryURLPrefix) else { return nil }
        return UUID(uuidString: String(text.dropFirst(entryURLPrefix.count)))
    }

    private func updateAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        let gained = status == .fullAccess && authorizationStatus != .fullAccess
        if authorizationStatus != status { authorizationStatus = status }
        if gained {
            // Nach der ersten Freigabe liefert ein neuer Store die Kalender zuverlässig.
            eventStore = EKEventStore()
            reloadCalendars()
            scheduleMirror(full: true)
        } else if status != .fullAccess, !calendars.isEmpty {
            calendars = []
            mirrorSources = []
            invalidateEvents()
        }
    }

    private func reloadCalendars() {
        guard hasFullAccess else { return }
        let all = eventStore.calendars(for: .event).sorted {
            let lhs = ($0.source?.title ?? "", $0.title)
            let rhs = ($1.source?.title ?? "", $1.title)
            return lhs < rhs
        }
        calendars = all
        let writable: Set<EKSourceType> = [.local, .calDAV, .exchange, .mobileMe]
        let order = ["iCloud": 0, "Google": 1, "Exchange": 2, "CalDAV": 3, "Auf meinem Mac": 4]
        let sources = eventStore.sources
            .filter { writable.contains($0.sourceType) }
            .map(CalendarSourceInfo.init(source:))
            .sorted { (order[$0.kind] ?? 9, $0.title) < (order[$1.kind] ?? 9, $1.title) }
        if mirrorSources != sources { mirrorSources = sources }
        invalidateEvents()
        updateMirroredCount()
    }

    private func invalidateEvents() {
        dayCache = nil
        revision &+= 1
    }

    private func startObserving() {
        let center = NotificationCenter.default
        // Änderungen im Kalender (auch eigene Spiegelungen, andere Apps, Synchronisation).
        tokens.append(center.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.hasFullAccess else { return }
                self.reloadCalendars()
            }
        })
        // Freigabe in den Systemeinstellungen erteilt oder entzogen.
        tokens.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateAuthorizationStatus() }
        })
        // Tageswechsel: „Heute“ zeigt die Termine des neuen Tages.
        tokens.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.invalidateEvents() }
        })
        // Regelmäßig vollständig abgleichen (z. B. Änderungen an älteren Tagen in den Berichten).
        let timer = Timer(timeInterval: Self.fullReconcileInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleMirror(full: true) }
        }
        RunLoop.main.add(timer, forMode: .common)
        periodicTimer = timer
        // Der Dienst lebt so lange wie die App; ein Abmelden im deinit ist nicht nötig.
    }
}
