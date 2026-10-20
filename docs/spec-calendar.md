# Takt – Kalender-Anbindung (EventKit)

Baut auf der v5-Datenbasis auf (`SPEC.md` › „v5 – Datenbasis“ › Kalender: `CalendarEventLink`,
`CalendarRule`, `entriesNeedingMirror`, `removeOrphanLinks`, `matchCalendarRule`). EventKit lebt
ausschließlich in der App (`Takt/Calendar/`), TaktCore kennt nur Kennungen und Regeln.

## Dateien

| Datei | Inhalt |
|---|---|
| `Takt/Calendar/CalendarService.swift` | `@MainActor @Observable`: Berechtigung, Kalender, Termine je Tag, Spiegelung, Abgleich |
| `Takt/Calendar/CalendarEventInfo.swift` | `CalendarEventInfo` (Termin ohne EventKit-Objekt), `CalendarSourceInfo` (Quelle für den Picker) |
| `Takt/Views/Today/TodayEvents.swift` | Terminspur-Segment, Liste „Termine heute“, Hinweis „Termin läuft“ |
| `Takt/Views/Today/TodayData.swift` | `EventItem`, `MeetingHint`, `events`, `allDayEvents`, `meetingHint`, `TodayActions.captureEvent` |
| `Takt/Views/Today/TodayScreen.swift` | Tagesleiste mit Terminspur, Einbindung von Hinweis und Liste |
| `Takt/Views/Today/TodayView.swift` | befüllt Termine (Regel-Projekt, „erfasst“), Termin → Eintrag, Lösch-Pfad |
| `Takt/Views/Today/EntryEditor.swift` | `EntryDraft.needsProject` (Projekt leer vorbelegt), Lösch-Pfad |
| `Takt/Settings/Sections/CalendarSettingsSection.swift` | Einstellungen „Kalender“ |

Verdrahtung in `TaktApp`: `CalendarService(store:settings:)` nach dem Store anlegen, als `@State`
halten und per `.environment(calendarService)` an Hauptfenster und Einstellungen geben. Ansichten
lesen ihn **optional** (`@Environment(CalendarService.self) var calendarService: CalendarService?`) –
ohne Verdrahtung bleibt „Heute“ wie bisher.

## Berechtigung

- `requestFullAccessToEvents()` (macOS 14+), Text `NSCalendarsFullAccessUsageDescription` in `project.yml`.
- Status wird beim Start, nach der Abfrage und bei jeder Aktivierung der App gelesen (Freigabe in
  den Systemeinstellungen). Nach der ersten Freigabe wird der `EKEventStore` neu erzeugt.
- Erteilt → `calendarShowEvents = true`. Abgelehnt → Knopf „Systemeinstellungen …“
  (Datenschutz › Kalender).

## Termine in „Heute“

- `events(on:)`: alle Termine des Tages aus den sichtbaren Kalendern, ohne abgesagte, sortiert.
  Sichtbar = `calendarVisibleIDs` (leer = alle) **ohne** den Spiegel-Kalender (bzw. ohne Spiegel-ID:
  ohne beschreibbare Kalender namens „Takt“). Ergebnis je Tag/Revision zwischengespeichert;
  `revision` steigt bei `.EKEventStoreChanged` und Tageswechsel (`.NSCalendarDayChanged`).
- Tagesleiste: eigene Spur 6 pt oberhalb der Eintragssegmente (Leiste dann 36 statt 26 pt hoch),
  Segmente in Kalenderfarbe mit 50 % Deckung, fein schraffiert, Tooltip „Titel · 14:00–15:00“.
  Das Zeitfenster (8–19 Uhr) wächst auch mit Terminen. Ganztägige Termine nicht in der Leiste,
  sondern als „Ganztägig: …“ in der Kopfzeile der Liste.
- Liste „Termine heute“ (nur bei `calendarShowEvents` und Zugriff): Farbstrich, Zeit, Titel, „läuft“,
  Regel-Projekt (Punkt + Name), Kalendername; rechts „Als Eintrag“ oder „✓ erfasst“. Erfasst =
  heutiger abgeschlossener Eintrag mit Beginn **und** Ende je ±1 min. Eingeklappt höchstens drei
  Termine ab dem ersten, der nicht „vorbei und erfasst“ ist; „Alle n Termine anzeigen“ klappt auf.
- „Als Eintrag“ öffnet den `EntryEditor` vorbelegt: Zeitraum des Termins, Projekt aus
  `store.matchCalendarRule(calendarName:title:attendeeDomains:)` – ohne Treffer leer
  („Bitte wählen“, Sichern erst nach Auswahl) –, Nächster Schritt = Titel, Tag „Meeting“.
  Teilnehmer-Domains kommen aus `attendees` und `organizer` (`mailto:` → Domain).
- Hinweiszeile, wenn ein Termin gerade läuft und ein Timer läuft: „Termin ‚Review Gerlach‘ läuft –
  Timer auf Website“. Mit Regel-Projekt ≠ laufendem Projekt zusätzlich „Wechseln zu <Projekt>“
  (startet das Projekt, der laufende Timer endet). Ohne Regel nur, wenn der laufende Eintrag nicht
  das Tag „Meeting“ trägt. Erfasste Termine lösen keinen Hinweis aus; × blendet ihn je Termin aus.

## Spiegelung

- Ein Kalender „Takt“ in der gewählten Quelle (Picker über `eventStore.sources`: iCloud, Google/CalDAV,
  Exchange, „Auf meinem Mac“). Gibt es dort schon einen beschreibbaren Kalender „Takt“, wird er
  übernommen. ID in `calendarMirrorCalendarID`. Lässt die Quelle kein Anlegen zu (z. B. Google über
  CalDAV), erscheint ein Hinweis: Kalender dort selbst anlegen, Quelle erneut wählen.
- Ein Ereignis je Eintrag: Titel „Projekt“ bzw. „Projekt · #Tag“, Notiz = Nächster Schritt,
  Zeitraum = Eintrag, URL `takt://entry/<UUID>`. Farbe kommt vom Kalender – kein Kalender je Projekt.
- `mirrorPendingEntries()`: `entriesNeedingMirror(since: jetzt − 30 Tage, minimumDuration:
  Mindestdauer)`, vorhandenes verknüpftes Ereignis aktualisieren, sonst anlegen; ein Commit, danach
  `setCalendarLink(… updatedAt: jetzt)`.
- Auslöser: Änderung von `store.todayEntries`/`store.running` (Stopp, Bearbeiten, auch aus Widget
  und Menüleiste) und der Spiegel-Einstellungen, gebündelt mit 5 s Verzögerung; App-Start (erster
  Durchlauf); alle 30 min; „Jetzt spiegeln“ sofort.
- Vollständiger Abgleich (Start, „Jetzt spiegeln“, höchstens alle 30 min) im Zeitraum der letzten
  30 Tage:
  1. `removeOrphanCalendarLinks()` und deren Ereignisse löschen;
  2. eigene Ereignisse (Takt-URL) ohne passenden Eintrag löschen: Eintrag gelöscht, läuft wieder,
     kürzer als die Mindestdauer, oder Dublette. Eigene Ereignisse ohne Verknüpfung werden
     übernommen (Verknüpfung mit `updatedAt = distantPast`, Inhalt wird neu geschrieben);
  3. Verknüpfungen lösen, deren Ereignis fehlt (im Kalender gelöscht) oder in einem anderen Kalender
     liegt (Quelle gewechselt) – diese Einträge werden neu gespiegelt.
  Lesefehler der Datenbank brechen den Abgleich ab (nie „alles gelöscht“ annehmen).
- Löschen: `TodayView` und `EntryEditor` rufen **vor** `store.deleteEntry` `calendarService.willDelete(entryId:)`
  auf; die Verknüpfung fällt danach per CASCADE. Andere Lösch-Wege fängt Schritt 2 des Abgleichs.
- Ausschalten: Rückfrage „Ereignisse behalten“ / „Ereignisse löschen“. Löschen entfernt alle Ereignisse
  mit Takt-URL im Spiegel-Kalender (letzte drei Jahre) und deren Verknüpfungen; der Kalender selbst bleibt.
- Quelle wechseln: neuer/vorhandener „Takt“ in der Quelle; bisherige Ereignisse bleiben im alten
  Kalender, die letzten 30 Tage landen im neuen.
- Sicherheit: Geschrieben/gelöscht wird nur im Spiegel-Kalender; gelöscht nur, wenn das Ereignis im
  verknüpften Kalender liegt, dieser „Takt“ heißt bzw. der Spiegel-Kalender ist und eine vorhandene
  Takt-URL zum Eintrag passt. Ereignisse anderer Kalender werden nie verändert.
- Log: Subsystem `dev.eremiya.takt`, Kategorie `calendar`.

## Einstellungen (Reiter „Kalender“)

1. **Kalender**: Status + „Zugriff erlauben“ (bzw. „Systemeinstellungen …“), Schalter
   „Termine in ‚Heute‘ anzeigen“.
2. **Angezeigte Kalender**: Häkchen je Kalender mit Farbe und Quelle (ohne „Takt“). Sind alle an,
   wird `calendarVisibleIDs` wieder leer (neue Kalender erscheinen automatisch).
3. **Zeiten in Kalender spiegeln**: Schalter (ein → Kalender anlegen, sofort spiegeln; aus → Rückfrage),
   Picker „Quelle“, Mindestdauer-Stepper (1, 2, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240 min),
   „n Ereignisse gespiegelt“ (Takt-Ereignisse im Spiegel-Kalender, letzte drei Jahre) mit „zuletzt hh:mm“,
   „Jetzt spiegeln“, Fehlertext.
4. **Regeln Termin → Projekt**: je Zeile Griff (Ziehen ordnet um → `reorderCalendarRules`), Art
   (Kalender / Titel enthält / Teilnehmer-Domain), Muster (gesichert bei Enter oder Verlassen, leer →
   alter Wert), Projekt, −; darunter eine Zeile zum Hinzufügen mit +.

## Prüfen

- Build: `xcodegen generate && xcodebuild -project Takt.xcodeproj -scheme Takt -configuration Debug
  -derivedDataPath .build/dd-cal build`.
- Render-Harness „Heute“ mit Terminen: `TodayData.sampleWithEvents` (DEBUG), Vorschau „Mit Terminen“.
