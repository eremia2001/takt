import Foundation
import TaktCore
import WidgetKit

/// Ein Timeline-Eintrag: Momentaufnahme aus der Datenbank plus Anzeigezeitpunkt.
/// Alle Zeitwerte werden aus `date` berechnet – nie aus `Date.now`.
struct TaktEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// Zeitpunkt, zu dem `snapshot` gelesen wurde (bezieht sich auf dessen Kalendertag).
    let snapshotDate: Date
    /// Darstellung; pro Timeline einmal gelesen, damit alle Einträge gleich aussehen.
    let style: WidgetStyle

    init(date: Date, snapshot: WidgetSnapshot, snapshotDate: Date? = nil, style: WidgetStyle = .plain) {
        self.date = date
        self.snapshot = snapshot
        self.snapshotDate = snapshotDate ?? date
        self.style = style
    }

    /// Dauer des laufenden Eintrags zum Zeitpunkt des Timeline-Eintrags.
    var runningDuration: TimeInterval {
        snapshot.running?.entry.duration(at: date) ?? 0
    }

    /// Tagessumme zum Zeitpunkt des Timeline-Eintrags: abgeschlossene Einträge plus der heutige
    /// Anteil des laufenden. Liegt `date` schon im nächsten Tag (Mitternacht innerhalb der
    /// Timeline), zählen die abgeschlossenen Einträge des Vortags nicht mehr.
    var todayTotal: TimeInterval {
        let calendar = Calendar.current
        let completed = calendar.isDate(snapshotDate, inSameDayAs: date) ? snapshot.todayCompleted : 0
        guard let running = snapshot.running else { return completed }
        let start = max(running.entry.startedAt, calendar.startOfDay(for: date))
        return completed + max(0, date.timeIntervalSince(start))
    }
}

struct Provider: TimelineProvider {
    /// Wie weit eine Timeline mit laufendem Timer vorausplant.
    static let runningHorizon = 60
    /// Spätestens nach dieser Zeit wird im Pause-Zustand neu geladen.
    static let idleRefresh: TimeInterval = 3600

    func placeholder(in context: Context) -> TaktEntry {
        TaktEntry(date: .now, snapshot: .placeholder, style: SharedSettings.widgetStyle)
    }

    func getSnapshot(in context: Context, completion: @escaping (TaktEntry) -> Void) {
        let now = Date.now
        // In der Widget-Galerie Beispieldaten zeigen, sonst echte Daten.
        let snapshot = context.isPreview ? .placeholder : Self.loadSnapshot(now: now)
        completion(TaktEntry(date: now, snapshot: snapshot, style: SharedSettings.widgetStyle))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaktEntry>) -> Void) {
        let now = Date.now
        completion(Self.timeline(
            for: Self.loadSnapshot(now: now),
            now: now,
            style: SharedSettings.widgetStyle
        ))
    }

    // MARK: Bausteine

    /// Liest die Momentaufnahme; bei jedem Fehler „nichts läuft, keine Projekte“.
    static func loadSnapshot(now: Date) -> WidgetSnapshot {
        guard let database = WidgetDatabase.open() else { return .empty }
        do {
            return try database.widgetSnapshot(now: now)
        } catch {
            return .empty
        }
    }

    /// Läuft ein Timer: Eintrag jetzt, danach einer pro Minutengrenze der laufenden Dauer
    /// für die nächsten 60 Minuten, dann neu laden. Läuft nichts: ein Eintrag, neu laden nach
    /// einer Stunde bzw. um Mitternacht (Tagessumme beginnt bei 0). Alle Einträge tragen
    /// denselben `style`; ein Wechsel in der App lädt die Timeline ohnehin neu.
    static func timeline(
        for snapshot: WidgetSnapshot,
        now: Date,
        style: WidgetStyle = .plain,
        calendar: Calendar = .current
    ) -> Timeline<TaktEntry> {
        let first = TaktEntry(date: now, snapshot: snapshot, snapshotDate: now, style: style)

        guard let running = snapshot.running else {
            let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
                ?? now.addingTimeInterval(idleRefresh)
            let refresh = min(now.addingTimeInterval(idleRefresh), midnight)
            return Timeline(entries: [first], policy: .after(refresh))
        }

        // Minutengrenzen relativ zum Start, damit „h:mm“ genau dann umspringt, wenn eine
        // volle Minute erreicht ist.
        let startedAt = running.entry.startedAt
        let elapsedMinutes = floor(max(0, now.timeIntervalSince(startedAt)) / 60)
        let following = (1...runningHorizon).map { offset in
            TaktEntry(
                date: startedAt.addingTimeInterval((elapsedMinutes + Double(offset)) * 60),
                snapshot: snapshot,
                snapshotDate: now,
                style: style
            )
        }
        return Timeline(entries: [first] + following, policy: .atEnd)
    }
}
