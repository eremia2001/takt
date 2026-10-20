import AppKit
import Foundation
import Observation
import os
import TaktCore
import UserNotifications

/// Ein zusammenhängender Abschnitt gleicher Aktivität, solange er läuft im Speicher; beim
/// Wechsel (oder spätestens nach 30 Minuten) wird er als `ActivitySample` gespeichert.
struct ActivitySegment: Identifiable, Equatable, Sendable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date
    var bundleID: String
    var windowTitle: String?
    var repoPath: String?
    var projectId: UUID?

    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }

    /// Was „gleiche Aktivität“ heißt: dieselbe App, dasselbe Repository (der Fenstertitel darf
    /// sich dann mit jeder Datei ändern) bzw. ohne Repository derselbe Titel – und dasselbe Projekt.
    var key: String { Self.key(bundleID: bundleID, windowTitle: windowTitle, repoPath: repoPath, projectId: projectId) }

    static func key(bundleID: String, windowTitle: String?, repoPath: String?, projectId: UUID?) -> String {
        let place = repoPath.map { "repo:" + $0.lowercased() } ?? "title:" + (windowTitle ?? "")
        return "\(bundleID.lowercased())|\(place)|\(projectId?.uuidString ?? "-")"
    }

    var sample: ActivitySample {
        ActivitySample(
            id: id, startedAt: startedAt, endedAt: endedAt, bundleID: bundleID,
            windowTitle: windowTitle, repoPath: repoPath, projectId: projectId
        )
    }

    init(sample: ActivitySample) {
        id = sample.id
        startedAt = sample.startedAt
        endedAt = sample.endedAt
        bundleID = sample.bundleID
        windowTitle = sample.windowTitle
        repoPath = sample.repoPath
        projectId = sample.projectId
    }

    init(id: UUID = UUID(), startedAt: Date, endedAt: Date, bundleID: String,
         windowTitle: String?, repoPath: String?, projectId: UUID?) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.repoPath = repoPath
        self.projectId = projectId
    }
}

/// Schlüssel in `userInfo` der Aktivitäts-Mitteilung; außerhalb der MainActor-Klasse, damit der
/// nicht isolierte Antwort-Handler sie lesen darf.
private enum ActivityNotificationID {
    static let request = "dev.eremiya.takt.activity"
    static let projectKey = "projectId"
    static let runningKey = "runningProjectId"
}

/// Aktivitäts-Erkennung: beobachtet die vorderste App (Bundle-ID, mit Bedienungshilfen-Freigabe
/// auch Fenstertitel und Git-Repository), speichert die Aktivität lokal und meldet, wenn der
/// laufende Timer nicht zur Arbeit passt – oder schlägt einen Start vor, wenn nichts läuft.
///
/// - Nur bei `AppSettings.activitySuggestionsEnabled`; alle 15 s und bei jedem App-Wechsel.
/// - Gleiche Aktivität verlängert den laufenden Abschnitt; gespeichert wird beim Wechsel, bei
///   Leerlauf (≥ 5 min ohne Eingabe), Ruhezustand, Sperre, Beenden und spätestens alle 30 min.
/// - Projekt: erste passende `ActivityRule`, sonst Repo-Name ≈ Projektname.
/// - Abgleich über die letzten `activityMismatchMinutes` Minuten: ≥ 70 % davon in Projekt Y.
///   Mitteilung höchstens einmal je (Timer-Projekt, Y, Stunde); „Ignorieren“ schweigt 2 h.
/// - Antworten kommen über `BreakReminder.addResponseHandler`. Log-Kategorie `activity`.
@MainActor
@Observable
final class ActivityMonitor {
    // MARK: Zustand für die Oberfläche

    /// Beobachtung läuft (Einstellung an).
    private(set) var isActive = false
    /// Bedienungshilfen-Freigabe (ohne sie nur App-Namen).
    private(set) var isTrusted = ActivityProbe.isTrusted
    /// Kein Eingang seit mindestens 5 Minuten oder Bildschirm gesperrt.
    private(set) var isIdle = false
    /// Laufender, noch nicht gespeicherter Abschnitt.
    private(set) var current: ActivitySegment?
    /// Letzte Beobachtung (auch ignorierte Apps nicht – die zählen gar nicht).
    private(set) var lastObservation: ActivityObservation?

    // MARK: Interna

    @ObservationIgnored private let store: TaktStore
    @ObservationIgnored private let settings: AppSettings
    /// Abgeschlossene Abschnitte der letzten 3 Stunden (für Abgleich und „seit … Min“).
    @ObservationIgnored private var history: [ActivitySegment] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    @ObservationIgnored private var probeInFlight = false
    @ObservationIgnored private var tickPending = false
    @ObservationIgnored private var isLocked = false
    @ObservationIgnored private var repoIndex = RepoIndex.empty
    @ObservationIgnored private var repoIndexBuiltAt: Date?
    @ObservationIgnored private var lastPrune: Date?
    /// Bereits gemeldete (Timer-Projekt, Projekt, Stunde) mit Zeitpunkt.
    @ObservationIgnored private var notifiedKeys: [String: Date] = [:]
    /// „Ignorieren“: (Timer-Projekt, Projekt) still bis …
    @ObservationIgnored private var silencedUntil: [String: Date] = [:]
    /// Zuletzt zugestellte Nachfrage, damit sie verschwindet, sobald sie erledigt ist.
    @ObservationIgnored private var deliveredProjectId: UUID?

    // MARK: Konstanten

    static let probeInterval: TimeInterval = 15
    /// Größte Lücke zwischen zwei Beobachtungen, die einen Abschnitt noch verlängert (3 Takte).
    static let maxGap: TimeInterval = 45
    static let idleThreshold: TimeInterval = 5 * 60
    /// Spätestens dann wird ein langer Abschnitt gespeichert und fortgesetzt (Absturzschutz).
    static let checkpointInterval: TimeInterval = 30 * 60
    /// Kürzere Abschnitte (schnelles Durchklicken) werden nicht gespeichert.
    static let minimumSegment: TimeInterval = 5
    static let historyWindow: TimeInterval = 3 * 3600
    /// Anteil des Abgleich-Zeitraums, den Projekt Y mindestens ausmachen muss.
    static let dominantShare = 0.7
    static let ignoreDuration: TimeInterval = 2 * 3600
    static let repoIndexLifetime: TimeInterval = 5 * 60
    static let pruneInterval: TimeInterval = 24 * 3600

    /// Für die Weiterleitung aus dem Notification-Delegate.
    private static weak var shared: ActivityMonitor?
    private static var responseHandlerInstalled = false
    static let logger = Logger(subsystem: "dev.eremiya.takt", category: "activity")

    init(store: TaktStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        Self.shared = self
        Self.installResponseHandler()
        // Schalter in den Einstellungen beobachten; das Umschalten selbst erst nach dem
        // Auswerten, damit nur `activitySuggestionsEnabled` verfolgt wird.
        observeContinuously { [weak self] in
            guard let self else { return }
            let enabled = self.settings.activitySuggestionsEnabled
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.setEnabled(enabled) }
            }
        }
    }

    // MARK: Öffentliche Schnittstelle

    /// Fragt die Bedienungshilfen-Freigabe an und öffnet die Systemeinstellungen.
    func requestAccessibility() {
        ActivityProbe.requestTrust()
    }

    /// Prüft die Freigabe neu (z. B. wenn die Einstellungen sichtbar sind).
    func refreshTrust() {
        let trusted = ActivityProbe.isTrusted
        if trusted != isTrusted { isTrusted = trusted }
    }

    /// Die letzten Abschnitte (laufender zuerst), aus Speicher und Datenbank (24 h).
    func recentSamples(limit: Int = 10) -> [ActivitySample] {
        let now = Date()
        var samples = store.activitySamples(in: DateInterval(start: now.addingTimeInterval(-24 * 3600), end: now.addingTimeInterval(1)))
        if let current { samples.append(current.sample) }
        return Array(samples.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }

    // MARK: Start / Stopp

    private func setEnabled(_ enabled: Bool) {
        if enabled, !isActive { start() } else if !enabled, isActive { stop() }
    }

    private func start() {
        isActive = true
        let now = Date()
        history = store.activitySamples(in: DateInterval(start: now.addingTimeInterval(-Self.historyWindow), end: now))
            .map(ActivitySegment.init(sample:))

        let timer = Timer(timeInterval: Self.probeInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { $0.tick() }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.closeCurrent(at: .now, reason: "Ruhezustand") }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.closeCurrent(at: .now, reason: "Benutzerwechsel") }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) {
            $0.isLocked = true
            $0.closeCurrent(at: .now, reason: "Bildschirmsperre")
        }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) {
            $0.isLocked = false
            $0.tick()
        }
        observe(NotificationCenter.default, NSApplication.willTerminateNotification) {
            $0.closeCurrent(at: .now, reason: "Beenden")
        }

        Self.logger.info("Aktivitäts-Erkennung gestartet (Bedienungshilfen: \(ActivityProbe.isTrusted ? "ja" : "nein", privacy: .public)).")
        tick()
    }

    private func stop() {
        closeCurrent(at: .now, reason: "ausgeschaltet")
        timer?.invalidate()
        timer = nil
        for observer in observers { observer.center.removeObserver(observer.token) }
        observers = []
        history = []
        isActive = false
        isIdle = false
        lastObservation = nil
        if deliveredProjectId != nil {
            NotificationCategories.remove(identifier: ActivityNotificationID.request)
            deliveredProjectId = nil
        }
        Self.logger.info("Aktivitäts-Erkennung beendet.")
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor (ActivityMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }

    // MARK: Beobachten

    private func tick() {
        guard isActive else { return }
        guard !probeInFlight else {
            tickPending = true
            return
        }
        let now = Date()
        refreshTrust()
        pruneIfNeeded(now: now)

        // Leerlauf oder Sperre: Abschnitt bei der letzten Eingabe beenden, nichts Neues beginnen.
        let idle = IdleDetector.secondsSinceLastInput()
        if isLocked || idle >= Self.idleThreshold {
            if !isIdle { isIdle = true }
            closeCurrent(at: now.addingTimeInterval(-idle), reason: "Leerlauf")
            return
        }
        if isIdle { isIdle = false }

        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier else { return }
        // Ignorierte Apps unterbrechen nichts: Der Abschnitt bleibt offen, verlängert sich aber nicht.
        if ActivityHeuristics.isIgnored(bundleID: bundleID, ownBundleID: Bundle.main.bundleIdentifier) {
            evaluate(now: now)
            return
        }

        let pid = app.processIdentifier
        let appName = app.localizedName
        ActivityAppNames.remember(appName, for: bundleID)
        let index = repoIndex
        let needsIndex = repoIndexBuiltAt.map { now.timeIntervalSince($0) > Self.repoIndexLifetime } ?? true

        probeInFlight = true
        Task { [weak self] in
            let (observation, freshIndex) = await Task.detached(priority: .utility) { () -> (ActivityObservation, RepoIndex?) in
                let fresh = needsIndex ? RepoIndex(roots: RepoIndex.defaultRoots()) : nil
                let observation = ActivityProbe.observe(pid: pid, bundleID: bundleID, appName: appName, index: fresh ?? index)
                return (observation, fresh)
            }.value
            guard let self else { return }
            self.probeInFlight = false
            if let freshIndex {
                self.repoIndex = freshIndex
                self.repoIndexBuiltAt = Date()
            }
            if self.isActive {
                let at = Date()
                self.ingest(observation, at: at)
                self.evaluate(now: at)
            }
            if self.tickPending {
                self.tickPending = false
                self.tick()
            }
        }
    }

    /// Übernimmt eine Beobachtung: gleicher Schlüssel und keine Lücke → verlängern, sonst den
    /// alten Abschnitt abschließen und einen neuen beginnen.
    private func ingest(_ observation: ActivityObservation, at now: Date) {
        if lastObservation != observation { lastObservation = observation }
        if observation.isTrusted != isTrusted { isTrusted = observation.isTrusted }

        let projectId = resolveProject(observation)
        let key = ActivitySegment.key(
            bundleID: observation.bundleID, windowTitle: observation.windowTitle,
            repoPath: observation.repoPath, projectId: projectId
        )

        if var segment = current {
            let gap = now.timeIntervalSince(segment.endedAt)
            if segment.key == key, gap <= Self.maxGap {
                segment.endedAt = now
                if let title = observation.windowTitle { segment.windowTitle = title }
                if segment.duration >= Self.checkpointInterval {
                    // Zwischenstand sichern und nahtlos weitermachen.
                    finish(segment)
                    current = ActivitySegment(
                        startedAt: now, endedAt: now, bundleID: segment.bundleID,
                        windowTitle: segment.windowTitle, repoPath: segment.repoPath, projectId: segment.projectId
                    )
                } else {
                    current = segment
                }
                return
            }
            // Wechsel: Der alte Abschnitt reicht bis jetzt, sofern ohne Lücke beobachtet.
            if gap <= Self.maxGap { segment.endedAt = now }
            finish(segment)
        }

        current = ActivitySegment(
            startedAt: now, endedAt: now, bundleID: observation.bundleID,
            windowTitle: observation.windowTitle, repoPath: observation.repoPath, projectId: projectId
        )
        Self.logger.debug("Neue Aktivität: \(observation.bundleID, privacy: .public), Repo \(observation.repoPath ?? "–", privacy: .private), Projekt \(projectId.flatMap { self.store.projectsById[$0]?.name } ?? "–", privacy: .private)")
    }

    /// Beendet den laufenden Abschnitt bei `date` (höchstens eine Lücke nach der letzten
    /// Beobachtung, nie vor seinem Beginn) und speichert ihn.
    private func closeCurrent(at date: Date, reason: String) {
        guard var segment = current else { return }
        segment.endedAt = max(segment.startedAt, min(date, segment.endedAt.addingTimeInterval(Self.maxGap)))
        current = nil
        finish(segment)
        Self.logger.debug("Abschnitt beendet (\(reason, privacy: .public)).")
    }

    /// Speichert einen abgeschlossenen Abschnitt (sofern nicht zu kurz) und merkt ihn sich.
    private func finish(_ segment: ActivitySegment) {
        guard segment.duration >= Self.minimumSegment else { return }
        if let saved = store.addActivitySample(segment.sample) {
            history.append(ActivitySegment(sample: saved))
        } else {
            history.append(segment)
            Self.logger.error("Aktivität nicht gespeichert.")
        }
        let cutoff = Date().addingTimeInterval(-Self.historyWindow)
        history.removeAll { $0.endedAt < cutoff }
    }

    /// Projekt zur Beobachtung: erste passende Regel (archivierte Projekte übersprungen), sonst
    /// Repository-Name ≈ Projektname.
    private func resolveProject(_ observation: ActivityObservation) -> UUID? {
        for rule in store.activityRules
        where rule.matches(bundleID: observation.bundleID, windowTitle: observation.windowTitle, repoPath: observation.repoPath) {
            if let project = store.projectsById[rule.projectId], !project.isArchived { return project.id }
        }
        guard let repoPath = observation.repoPath else { return nil }
        let name = (repoPath as NSString).lastPathComponent
        return ActivityHeuristics.guessProject(repoName: name, projects: store.projects.map { ($0.id, $0.name) })
    }

    private func pruneIfNeeded(now: Date) {
        if let lastPrune, now.timeIntervalSince(lastPrune) < Self.pruneInterval { return }
        lastPrune = now
        let removed = store.pruneActivitySamples(olderThan: now.addingTimeInterval(-AppDatabase.activitySampleRetention))
        if removed > 0 { Self.logger.info("\(removed) alte Aktivitäts-Abschnitte gelöscht.") }
    }

    // MARK: Abgleich

    private func evaluate(now: Date) {
        guard isActive, !isIdle else { return }
        let running = store.running

        // Erledigt (Timer läuft inzwischen auf dem vorgeschlagenen Projekt): Mitteilung entfernen.
        if let delivered = deliveredProjectId, running?.project.id == delivered {
            NotificationCategories.remove(identifier: ActivityNotificationID.request)
            deliveredProjectId = nil
        }

        let window = TimeInterval(settings.activityMismatchMinutes) * 60
        var from = now.addingTimeInterval(-window)
        if let running {
            // Erst nach dem Start des Timers zählen – sonst meldet sich Takt gleich nach einem Wechsel.
            from = max(from, running.entry.startedAt)
        } else {
            // Ohne Timer ab dem letzten Stopp zählen; in einer Pomodoro-Pause nie vorschlagen.
            if let pomodoro = SharedSettings.pomodoro, pomodoro.enabled, pomodoro.phase.isBreak, pomodoro.isActive(at: now) {
                return
            }
            if let lastStop = store.todayEntries.compactMap(\.endedAt).max() { from = max(from, lastStop) }
        }
        guard from < now else { return }

        let totals = projectTotals(from: from, to: now)
        guard let best = totals.max(by: { $0.value < $1.value }),
              best.value >= window * Self.dominantShare,
              let project = store.projectsById[best.key], !project.isArchived
        else { return }
        let projectId = best.key
        let seconds = best.value
        if running?.project.id == projectId { return }

        let pair = Self.pairKey(running: running?.project.id, project: projectId)
        silencedUntil = silencedUntil.filter { $0.value > now }
        if silencedUntil[pair] != nil { return }
        let hourKey = pair + "|" + Self.hourStamp(now)
        notifiedKeys = notifiedKeys.filter { now.timeIntervalSince($0.value) < 2 * 3600 }
        guard notifiedKeys[hourKey] == nil else { return }
        notifiedKeys[hourKey] = now

        let minutes = max(1, Int((max(streak(of: projectId, now: now), seconds) / 60).rounded()))
        let place = placeLabel(for: projectId, project: project)

        if let running {
            notify(
                title: "Passt der Timer?",
                body: "Timer läuft auf \(running.project.name), du arbeitest aber seit \(minutes) Min in \(place)",
                projectId: projectId, runningId: running.project.id, actions: true
            )
            Self.logger.info("Abweichung: Timer auf \(running.project.name, privacy: .private), erkannt \(project.name, privacy: .private) (\(minutes) Min).")
        } else if settings.activityAutoStartEnabled {
            if store.start(projectId: projectId) {
                notify(
                    title: "Timer gestartet: \(project.name)",
                    body: "Du arbeitest seit \(minutes) Min in \(place).",
                    projectId: projectId, runningId: nil, actions: false
                )
                Self.logger.info("Automatisch gestartet: \(project.name, privacy: .private) (\(minutes) Min).")
            }
        } else {
            notify(
                title: "Timer starten?",
                body: "Du arbeitest seit \(minutes) Min in \(place) – Timer starten?",
                projectId: projectId, runningId: nil, actions: true
            )
            Self.logger.info("Startvorschlag: \(project.name, privacy: .private) (\(minutes) Min).")
        }
    }

    /// Erfasste Sekunden je Projekt im Zeitraum (laufender Abschnitt eingeschlossen).
    private func projectTotals(from: Date, to: Date) -> [UUID: TimeInterval] {
        var totals: [UUID: TimeInterval] = [:]
        for segment in allSegments {
            guard let projectId = segment.projectId else { continue }
            let overlap = min(segment.endedAt, to).timeIntervalSince(max(segment.startedAt, from))
            if overlap > 0 { totals[projectId, default: 0] += overlap }
        }
        return totals
    }

    /// Wie lange schon (weitgehend) ununterbrochen in diesem Projekt gearbeitet wird: rückwärts
    /// summieren, bis eine Lücke > 5 min oder ein anderes Projekt > 2 min dazwischenkommt.
    private func streak(of projectId: UUID, now: Date) -> TimeInterval {
        var cursor = now
        var total: TimeInterval = 0
        for segment in allSegments.sorted(by: { $0.endedAt > $1.endedAt }) {
            if cursor.timeIntervalSince(segment.endedAt) > 5 * 60 { break }
            if segment.projectId == projectId {
                total += segment.duration
            } else if segment.duration > 2 * 60 {
                break
            }
            cursor = min(cursor, segment.startedAt)
        }
        return total
    }

    private var allSegments: [ActivitySegment] {
        current.map { history + [$0] } ?? history
    }

    /// „eventbuster-app (EventBuster)“ – Repository, sonst App; gleicher Name nur einmal.
    private func placeLabel(for projectId: UUID, project: Project) -> String {
        let latest = allSegments.filter { $0.projectId == projectId }.max { $0.endedAt < $1.endedAt }
        let label = latest?.repoPath.map { ($0 as NSString).lastPathComponent }
            ?? latest.map { ActivityAppNames.name(for: $0.bundleID) }
        guard let label, ActivityHeuristics.fold(label) != ActivityHeuristics.fold(project.name) else {
            return project.name
        }
        return "\(label) (\(project.name))"
    }

    private func notify(title: String, body: String, projectId: UUID, runningId: UUID?, actions: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if actions { content.categoryIdentifier = NotificationCategories.Activity.category }
        content.userInfo = [
            ActivityNotificationID.projectKey: projectId.uuidString,
            ActivityNotificationID.runningKey: runningId?.uuidString ?? "",
        ]
        NotificationCategories.deliverNow(identifier: ActivityNotificationID.request, content: content)
        deliveredProjectId = actions ? projectId : nil
    }

    private static func pairKey(running: UUID?, project: UUID) -> String {
        "\(running?.uuidString ?? "-")→\(project.uuidString)"
    }

    private static func hourStamp(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)-\(parts.hour ?? 0)"
    }

    // MARK: Antworten auf Mitteilungen

    /// Meldet sich einmal bei `BreakReminder` an (dem einzigen Delegate des Notification-Centers).
    /// Der Handler ist nicht isoliert: Er prüft nur die Kategorie und gibt die Arbeit an den
    /// MainActor weiter.
    private static func installResponseHandler() {
        guard !responseHandlerInstalled else { return }
        responseHandlerInstalled = true
        BreakReminder.addResponseHandler(makeResponseHandler())
    }

    private nonisolated static func makeResponseHandler() -> (UNNotificationResponse) -> Bool {
        { response in
            let content = response.notification.request.content
            guard content.categoryIdentifier == NotificationCategories.Activity.category else { return false }
            let action = response.actionIdentifier
            let projectId = (content.userInfo[ActivityNotificationID.projectKey] as? String).flatMap(UUID.init(uuidString:))
            let runningId = (content.userInfo[ActivityNotificationID.runningKey] as? String).flatMap(UUID.init(uuidString:))
            Task { @MainActor in
                shared?.handleResponse(action: action, projectId: projectId, runningId: runningId)
            }
            return true
        }
    }

    private func handleResponse(action: String, projectId: UUID?, runningId: UUID?) {
        guard let projectId else { return }
        deliveredProjectId = nil
        switch action {
        case NotificationCategories.Activity.switchProject, NotificationCategories.Activity.startProject:
            guard let project = store.projectsById[projectId], !project.isArchived else {
                Self.logger.error("Vorgeschlagenes Projekt gibt es nicht mehr.")
                return
            }
            guard store.running?.project.id != projectId else { return }
            if store.start(projectId: projectId) {
                Self.logger.info("Aus Mitteilung gestartet: \(project.name, privacy: .private).")
            }
        case NotificationCategories.Activity.ignore:
            silencedUntil[Self.pairKey(running: runningId, project: projectId)] = Date().addingTimeInterval(Self.ignoreDuration)
            Self.logger.info("Vorschlag für 2 h ignoriert.")
        default:
            // Klick auf die Mitteilung selbst oder Verwerfen: nichts tun.
            break
        }
    }
}
