# Takt – Spezifikation MVP

Minimalistischer Zeittracker für macOS mit Widget auf dem Schreibtisch.
Zielgruppe: ein Freiberufler (Softwareentwicklung), Business- und Privatprojekte.

## Grundsätze

- **Ein Blick, eine Aussage.** Das Widget zeigt nur, was gerade läuft (oder dass nichts läuft).
- **Beobachten, nicht erziehen.** Keine Gamification, keine aufdringlichen Pop-ups, keine tickenden Sekunden.
- **Apple-Stil.** Systemschrift, Systemhintergrund, viel Luft, Projektfarbe als einziger Akzent.
- **Lokal.** Alle Daten liegen in einer SQLite-Datei auf dem Mac.

## Entscheidungen

| Thema | Entscheidung |
|---|---|
| Business/Privat | Markierung am Projekt, keine Kunden |
| Stundensätze | nicht im MVP |
| Sync | nicht im MVP, nur lokal |
| Stack | Swift 5-Modus, SwiftUI, WidgetKit, App Intents, GRDB/SQLite, Swift Charts, XcodeGen |
| Datenaustausch App ↔ Widget | SQLite im App-Group-Container `N5GJ4D394X.group.dev.eremiya.takt` (Team-Präfix-Form, braucht kein Portal-Profil), Darwin-Notification als Anstoß |
| Musik | Spotify-Desktop-App per Apple Events (AppleScript), später Apple Music |
| Timer-Anzeige | `h:mm`, Timeline mit Minuten-Einträgen statt `.timer`-Style (keine Sekunden) |

## MVP-Funktionen

### Widget
- Größen: klein, mittel.
- Zustand *läuft*: Farbpunkt, Projektname, Dauer `h:mm`, Stopp-Knopf.
- Zustand *Pause*: „Nichts läuft“, Start-Knöpfe für max. 3 zuletzt genutzte Projekte.
- Mittel zusätzlich: Tagessumme als eine Zahl.
- Kein Diagramm, keine Listen, keine Einstellungen. Klick öffnet die App.

### Zeiterfassung
- Start/Stopp pro Projekt, immer nur ein laufender Timer (Start stoppt den vorherigen).
- Beim Stoppen optional Notiz „Nächster Schritt“, wird beim nächsten Start gezeigt.
- Einträge bearbeiten, löschen, manuell anlegen.
- Vergessener Timer: Nachfrage nach einstellbarer Grenze (Standard 8 h).

### Projekte
- Name, Farbe, Business/Privat, optionale Spotify-Playlist.
- Archivieren statt löschen, manuelle Reihenfolge.

### Fokus
- Pausenerinnerung: eine Mitteilung nach einstellbarer Dauer (Standard 75 Min), abschaltbar.
- Kennzahlen im Bericht: Projektwechsel pro Tag, längster ununterbrochener Block.

### Musik
- Pro Projekt optionale Playlist, globale Standard-Playlist.
- Start → Playlist, Stopp → Pause, Pausenerinnerung → Pause. Globaler Schalter.

#### Quellen und Anbieter (`Takt/Music/`)
- `Project.musicSource` bzw. „Standard-Quelle“ (`defaultPlaylistURI`) ist Text, erkannt von
  `MusicSource.parse` und gespeichert als `storageString`:
  | Eingabe | Quelle | Anbieter |
  |---|---|---|
  | `spotify:…`, `open.spotify.com/{playlist,album,track}/ID` | Spotify (Link → URI) | Spotify |
  | `https://music.apple.com/…`, `music://…` | Apple-Music-Link | Apple Music |
  | `applemusic:playlist:Name`, „Apple Music: Name“ | Playlist der eigenen Mediathek | Apple Music |
  | `music.youtube.com/…`, `youtube.com/…`, `youtu.be/…`, sonstige `http(s)`-Links | Web-Link | Browser |
  | bloßer Name („Fokus“) | nur bei bevorzugtem Anbieter Apple Music eine Playlist, sonst ungültig | |
- Auswahl: Projektquelle → sonst Standard-Quelle; der Anbieter folgt der Quelle. Der
  „bevorzugte Anbieter“ (`musicProvider`) entscheidet nur bei mehrdeutigem Text und beim
  Pausieren, wenn Takt in dieser Sitzung noch nichts gestartet hat. „Keine“ schaltet die
  Steuerung ganz ab.
- Stopp und Pausenerinnerung pausieren den zuletzt aktiven Anbieter. Projektwechsel auf
  einen anderen Anbieter: alten pausieren, neuen starten. Gleiche Quelle läuft schon → nichts tun.
  „Laufende Musik übernehmen“ aus → spielt der Anbieter schon etwas, bleibt es dabei.
- **Spotify:** AppleScript `play track "<URI>"`, Start der App mit bis zu 8 Versuchen.
- **Apple Music (Musik-App):** AppleScript. Zuverlässig: `play playlist "<Name>"` für Playlists
  der Mediathek (nach App-Start wie Spotify mit Wiederholung), `pause`, `player state`.
  Katalog-Links werden als `music://…` nur *geöffnet* – die Musik-App zeigt sie an, spielt
  aber nicht; ein folgendes `play` würde den vorherigen Titel fortsetzen und wird nicht
  gesendet. Läuft beim Öffnen Musik, wird sie vorher pausiert.
- **Browser:** Link im Standardbrowser öffnen. Der Zustand im Browser ist nicht lesbar
  (`isPlaying` = false); „übernehmen“ greift nicht. Gleicher Link bei Projektwechsel →
  kein zweiter Tab. Pause nur per Medientaste Play/Pause (Schalter
  `browserPauseWithMediaKey`), nur wenn Takt den Link geöffnet und noch nicht pausiert hat
  und der Browser läuft. Die Medientaste wirkt auf „Aktuell läuft“ (nicht zwingend den
  Browser) und schaltet um; sie braucht die Berechtigung „Bedienungshilfen“.
- Berechtigungen: Automation (Takt → Spotify/Musik) fragt macOS beim ersten Befehl ab.

### Hauptapp
- Heute: Zeitstrahl, laufender Timer, Einträge bearbeiten.
- Berichte: Tag/Woche/Monat/frei, Summen pro Projekt, Business vs. Privat, Fokus-Kennzahlen, ein Balkendiagramm.
- Projekte: Liste, anlegen, bearbeiten, archivieren.
- Einstellungen: Pausenerinnerung, Musik, Grenze vergessener Timer, Menüleiste an/aus.
- Menüleiste optional.

### Daten
- CSV-Export für Zeitraum. CSV-Import aus Toggl.

### Tastatur
- Globaler Kurzbefehl Start/Stopp letztes Projekt. Aktionen als App Intents (Kurzbefehle, Spotlight, Siri).

## Später
Stundensätze/Rechnungen, geplanter Block im Widget (Datenbasis siehe „Widget v2“), Schätzung vs. Ist, Aufgaben, iCloud/iPhone,
Apple Music, automatische App-Erkennung, Kalender.

## Umsetzungsreihenfolge

1. Projektgerüst, Datenmodell, Widget in beiden Zuständen echt auf dem Schreibtisch → Gestaltung abstimmen
2. Hauptapp „Heute“ + „Projekte“, Bearbeiten von Einträgen
3. Spotify-Steuerung, Pausenerinnerung, „Nächster Schritt“
4. Berichte + Kennzahlen, CSV-Export/-Import
5. Menüleiste, globaler Kurzbefehl, Feinschliff

## Abrechnung & Berichte (v2)

Ergänzt das MVP um Stundensätze, Abrechenbarkeit, Berichte, CSV-Export und Toggl-Import.
Die Tabelle „Entscheidungen“ oben (keine Kunden, keine Stundensätze) gilt insoweit nicht mehr.

### Datenmodell (Migration `v2`)

| Feld | Typ | Bedeutung |
|---|---|---|
| `Project.hourlyRate` | `Decimal?`, SQLite **TEXT** | Stundensatz; `nil` = Standard-Stundensatz aus den Einstellungen (falls gesetzt) |
| `Project.isBillable` | `Bool` | Vorgabe für alle Einträge; Standard = `isBusiness` (Migration: `isBillable = isBusiness`) |
| `Project.client` | `String?` | Kunde, freier Text |
| `Project.musicSource` | `String?` | beliebige URI/URL (Spotify, YouTube Music, Apple Music, `applemusic:playlist:<Name>`); Migration übernimmt `playlistURI` |
| `TimeEntry.isBillable` | `Bool?` | `nil` = vom Projekt erben; `effectiveBillable(project:)` |

- **Decimal-Speicherung:** als TEXT in POSIX-Schreibweise (`"92.35"`). GRDB 7 liest und schreibt
  `Decimal` nativ so – verlustfrei, kein Double-Rundungsfehler bei Geldbeträgen.
- `playlistURI` bleibt als veralteter Alias (Computed Property → `musicSource`), damit bestehender
  Code baut. Die alte Spalte `playlistURI` bleibt in der Datenbank stehen (Rückweg zu v1 möglich),
  wird aber nicht mehr geschrieben.
- Migrationen löschen nie Daten; geprüft mit einer echten v1-Datenbank (Tests + Sicherung
  `takt.sqlite.bak-v1` beim ersten Start der v2-App).

### Berichte (`Reports.swift`)

- Zeiträume: Tag, Woche, Monat, frei. **Wochen beginnen immer montags, KW nach ISO 8601** – auch
  wenn der Systemkalender anders eingestellt ist. Titel fest deutsch:
  „Dienstag, 20. Oktober 2026“, „KW 43 · 19.–25. Okt. 2026“, „Oktober 2026“, „1.–15. Okt. 2026“.
- Einträge werden an den Zeitraumgrenzen zugeschnitten, laufende zählen bis „jetzt“.
- **Rundung aufwärts, je Eintrag** (nach dem Zuschneiden), Schrittweiten 6/15/30 Minuten oder keine.
  Ungerundete Werte (`duration`, `total`, `billable`) und gerundete (`rounded…`) stehen nebeneinander;
  Beträge beruhen immer auf der gerundeten abrechenbaren Zeit. Toleranz 1 ms gegen Gleitkomma-Rauschen.
- **Betrag** = gerundete abrechenbare Sekunden / 3600 × Satz, kaufmännisch auf Cent je Projektzeile.
  Satz = Projektsatz, sonst Standard-Stundensatz; ohne Satz kein Betrag (`nil`).
- Tages-Buckets lückenlos für jeden Kalendertag; Einträge über Mitternacht werden anteilig verteilt.
  Business/Privat nach `Project.isBusiness`, abrechenbar nach `effectiveBillable`.

### CSV-Export (`CSVExport.swift`)

- Für deutsches Excel: Trennzeichen `;`, Dezimalkomma, UTF-8 mit BOM, Zeilenende CRLF, Felder mit
  `;`, `"` oder Zeilenumbruch in Anführungszeichen (`"` verdoppelt).
- Einträge: Datum; Start; Ende; Dauer (h:mm, ungerundet); Dauer (dezimal, gerundet, 2 Stellen);
  Projekt; Kunde; Business/Privat; Abrechenbar (ja/nein); Stundensatz; Betrag (nur abrechenbar mit
  Satz); Notiz („Nächster Schritt“). Laufende Einträge: Ende leer, Dauer bis jetzt.
- Summen: Zeile „Zeitraum“, Leerzeile, Projekttabelle, Summenzeile.

### Toggl-Import (`TogglImport.swift`)

- Liest den „Detailed report“ (CSV, `,`, `YYYY-MM-DD`, `HH:MM:SS`) mit eigenem RFC-4180-Parser
  (Anführungszeichen, Kommas/Zeilenumbrüche im Feld, CRLF, BOM). Pflicht: Start date/time und
  End date/time oder Duration. Kaputte Zeilen werden übersprungen und als Hinweis gemeldet.
- Ablauf: `parse` → Vorschau → Mapping Toggl-Projekt → vorhandenes Projekt oder neu
  (`suggestedTogglMapping` schlägt gleichnamige Projekte vor) → `importToggl` in einer Transaktion.
- „Neu anlegen“ verwendet ein vorhandenes Projekt mit gleichem Namen (Groß-/Kleinschreibung egal),
  damit ein zweiter Import keine doppelten Projekte erzeugt.
- **Dublettenregel:** Ein Eintrag wird übersprungen, wenn im Zielprojekt bereits ein Eintrag mit
  gleichem Start und gleichem Ende (±1 s) existiert – auch innerhalb derselben Datei.
- Toggl „Billable“ wird nur gespeichert, wenn es vom Projekt abweicht; sonst erbt der Eintrag.
  Die Toggl-Beschreibung landet in der Notiz (`nextStep`).

### Einstellungen

Reiter „Allgemein · Musik · Fokus · Widget · Abrechnung“. Abrechnung: Rundung, Währung
(3 Buchstaben, Standard EUR), Standard-Stundensatz. In `AppSettings` bereits angelegt für
Folgearbeiten: `musicProvider` (Spotify/Apple Music/Browser/keine), `browserPauseWithMediaKey`,
`menuBarEnabled`, `hideDockIcon`, `globalShortcutEnabled`, `globalShortcutKeyCode` (17 = T),
`globalShortcutModifiers` (⌃⌥⌘).

## Menüleiste & Kurzbefehl

### Menüleiste (`Takt/MenuBar/`)
- `MenuBarExtra` im Stil `.window`, ein- und ausblendbar über `menuBarEnabled` (`isInserted`;
  entfernt der Nutzer das Symbol per ⌘-Ziehen, schaltet sich die Einstellung mit aus).
- **Anzeige:** läuft ein Timer → Farbpunkt (Projektfarbe, als Nicht-Template-Bild) und
  „Projektname · h:mm“ (Namen ab 22 Zeichen gekürzt), sonst nur das Symbol `circle.dotted`.
  Aktualisierung minütlich zur vollen Minute über den Takt des `MenuBarController`, nach dem
  Aufwachen sofort.
- **Fenster (300 pt):** oben eine Karte wie das mittlere Widget bzw. die Farbkarte in „Heute“
  (läuft: Farbfläche mit Name, „seit 09:12 · heute 5:40“, Dauer, Stopp-Knopf; Pause: „Nichts läuft“
  und Tagessumme), darunter alle aktiven Projekte (Farbpunkt, Name, heutige Zeit; Klick = Start,
  das laufende ist farbig hinterlegt; ab 10 Projekten scrollt die Liste), unten „Takt öffnen“,
  „Einstellungen…“, „Beenden“.
- Stopp aus der Menüleiste: sofort, ohne Notiz „Nächster Schritt“.
- **Dock-Symbol:** `hideDockIcon` setzt `NSApp.setActivationPolicy(.accessory)`, sonst `.regular`,
  sofort wirksam. Nur zusammen mit der Menüleiste (sonst wäre Takt nicht mehr erreichbar); der
  Schalter ist ohne Menüleiste ausgegraut. „Takt öffnen“ aktiviert die App ausdrücklich und holt das
  Hauptfenster nach vorn bzw. öffnet es neu (`WindowGroup(id: "main")`).

### Globaler Kurzbefehl
- Standard ⌃⌥⌘T, frei wählbar. Registrierung per Carbon `RegisterEventHotKey` (keine
  Drittbibliothek, keine Bedienungshilfen-Berechtigung); bei jeder Änderung neu angemeldet.
  Lehnt macOS die Kombination ab (anderswo belegt), zeigen die Einstellungen einen Hinweis.
- Aktion: läuft ein Timer → stoppen (ohne Notiz), sonst `lastUsedProject` starten (Fallback:
  erstes aktives Projekt).
- Rückmeldung ohne Systemmitteilung: kleine Kapsel unten mittig auf dem Bildschirm mit dem
  Mauszeiger, 1,5 s sichtbar, nicht aktivierend und klick-durchlässig:
  „▶︎ Kundenportal gestartet“ / „■ Kundenportal gestoppt · 1:24“.
- Einstellungen „Allgemein“: Menüleiste anzeigen, Dock-Symbol ausblenden, Kurzbefehl aktiv,
  Aufnahmefeld (Klick → „Tasten drücken…“, verlangt ⌃, ⌥ oder ⌘, Esc bricht ab, Anzeige als
  Symbolfolge nach aktueller Tastaturbelegung), „Zurücksetzen“ auf ⌃⌥⌘T. Während der Aufnahme ist
  der alte Kurzbefehl abgemeldet.

### Vergessener Timer (`ForgottenTimerGuard`)
- Prüft alle 60 s, beim Aktivwerden der App und kurz nach dem Start, ob der laufende Eintrag
  länger als `forgottenTimerHours` läuft. Pro Eintrag eine Nachfrage; nach „Läuft weiter“
  frühestens 2 h später erneut. Der Zustand liegt nur im Speicher (nach einem Neustart der App
  wird höchstens einmal erneut gefragt).
- App aktiv → `NSAlert` als Sheet am Hauptfenster (ohne sichtbares Fenster modal):
  „Läuft ‚Kundenportal‘ wirklich noch?“ / „Gestartet 09:12, seit 8:05.“ (bei älterem Start mit
  „gestern“ bzw. Datum). Knöpfe „Läuft weiter“, „Jetzt stoppen“, „Stoppen um …“.
- App nicht aktiv → Mitteilung mit Kategorie `dev.eremiya.takt.forgotten-timer` und denselben
  Aktionen. Klick auf die Mitteilung selbst holt Takt nach vorn und zeigt den Alert.
  Antworten laufen über das Delegate von `BreakReminder` (`UNUserNotificationCenter` kennt nur
  eines), das sie an `ForgottenTimerGuard` weiterreicht.
- „Stoppen um …“ stoppt jetzt und zeigt „Heute“ (über `takt://today` an diese App), damit der
  Nutzer das Ende im Eintrag korrigiert. Wurde der Eintrag inzwischen anderswo gestoppt, bewirkt
  eine späte Antwort nichts.

## Widget v2 – Datenbasis

Grundlage für den Ausbau des Schreibtisch-Widgets (großes Widget, Ein-Projekt-Widget, Wechseln,
geplanter Block, Budget). Die Oberfläche steht unten unter „Widget v2 – Oberfläche“; sie ersetzt
für das Widget die MVP-Regeln (nur klein/mittel, keine Listen, keine Einstellungen).

### Datenmodell (Migration `v3`)

| Feld/Tabelle | Typ | Bedeutung |
|---|---|---|
| `Project.budgetHours` | `Decimal?`, SQLite **TEXT** | Stundenbudget; `nil` = keins. Wie `hourlyRate` in POSIX-Schreibweise (`"12.5"`) |
| `plannedBlock` | Tabelle | `id` (UUID), `projectId` (FK → `project`, `ON DELETE CASCADE`), `startAt`, `note?`, `createdAt` |

- **Modell „nächster Block“:** Es gibt höchstens einen geplanten Block. `setPlannedBlock` ersetzt alle
  vorhandenen (ältere/abgelaufene verschwinden dabei), `clearPlannedBlock` entfernt ihn.
- **Lesen:** `plannedBlock(now:)` liefert ihn nur, solange `startAt >= now − 4 h` – ein gerade
  fälliger Block bleibt sichtbar und startbar, ältere werden ignoriert.
- **Start:** `startTimer` löscht in derselben Transaktion einen Block desselben Projekts, wenn er
  fällig war (`startAt ≤ now + 15 min`) – auch wenn das Projekt schon lief. „Jetzt starten“ in der App
  erledigt den Block immer, auch einen später geplanten.
- **Budget:** `budgetUsage(projectId:now:)` summiert alle Einträge des Projekts (nicht nur heute),
  laufende bis `now`; Budget in Sekunden (`Project.budgetInterval`, `nil` bei keinem/≤ 0).

### Momentaufnahme (`WidgetSnapshot`)

Bisherige Felder (`running`, `recent`, `todayCompleted`) und der alte Initialisierer bleiben; neu:

| Feld | Inhalt |
|---|---|
| `switchTargets` | max. 2 zuletzt genutzte andere Projekte für „Wechseln“ (ohne laufendes) |
| `allProjects` | alle aktiven Projekte nach `sortOrder`, laufendes eingeschlossen |
| `todayEntries` | `[TodayEntry]` (`projectId`, `colorHex`, `startedAt`, `endedAt?`), heutiger Kalendertag, auf den Tag zugeschnitten, alle Projekte |
| `runningNextStep` | „Nächster Schritt“ vom vorherigen Lauf des laufenden Projekts |
| `plannedBlock` | `PlannedBlockInfo` (`project`, `startAt`, `note`); nicht bei archiviertem Projekt |
| `breakReminderMinutes` | aus `SharedSettings`, `nil` bei ausgeschalteter Erinnerung |
| `runningBudget` | `BudgetInfo` (`used` bis zur Momentaufnahme, `budget`, `completed` ohne laufenden Eintrag) nur, wenn das Projekt ein Budget hat |
| `fixedProjectID`, `fixedProjectRunningElsewhere` | Ein-Projekt-Widget, siehe unten |

- Wie bei `todayCompleted` rechnet das Widget die laufende Dauer selbst minütlich dazu:
  `BudgetInfo.used(at:runningSince:)`, `fraction(at:runningSince:)`.
- **Ein-Projekt-Widget** `widgetSnapshot(now:calendar:fixedProjectID:)`: `recent`, `switchTargets`
  und `allProjects` enthalten nur dieses Projekt (gibt es es nicht mehr: leer; `recent`/`switchTargets`
  ohne es, wenn es läuft). `running` nur, wenn dieses Projekt läuft; läuft ein anderes, ist
  `fixedProjectRunningElsewhere` gesetzt. `todayCompleted` und `plannedBlock` nur für dieses Projekt,
  `runningBudget` ist dessen Budget – **auch im Ruhezustand**. `todayEntries` bleibt vollständig
  (per `projectId` filterbar).
- `placeholder` zeigt einen laufenden Timer mit Budget (12:30 / 40 h), „Nächster Schritt“, Tagesleiste
  und einen geplanten Block.

### Gemeinsame Einstellungen

`SharedSettings` (App-Group-Suite) zusätzlich: `breakReminderEnabled` (Standard an) und
`breakReminderMinutes` (Standard 75). `AppSettings` spiegelt beide bei jeder Änderung (und einmal beim
Start) dorthin und lädt die Widget-Timelines neu. `SharedSettings.widgetStyle` ist der **Standardstil
für neue Widgets**.

### App

- **Projekte:** Feld „Stundenbudget“ (optional, Zahl > 0, Komma oder Punkt). In der Liste dezent
  „12:30 / 40 h“ mit schmalem Balken in Projektfarbe, ab 80 % Orange, über 100 % Rot; läuft das
  Projekt, minütlich aktualisiert.
- **Heute:** unter der Karte „Nächster Block“: entweder „14:00 · Kundenportal“ (+ Notiz, „fällig“ ab
  Beginn, Klick = ändern), „Jetzt starten“, „×“ – oder „Block planen …“. Popover: Projekt, Uhrzeit
  (Standard nächste volle Viertelstunde; liegt sie mehr als 5 Minuten zurück, gilt morgen) und
  Notiz. Schreiben über den Store wie alle Änderungen (Darwin-Notification + Widget-Reload).
- **Mitteilung:** Erreicht ein geplanter Block seinen Beginn und läuft kein Timer, kommt
  „Geplant: Kundenportal um 14:00“ (Notiz bzw. „Jetzt starten?“) mit Aktion „Starten“
  (Kategorie `dev.eremiya.takt.planned-block`, Antwort über das Delegate von `BreakReminder`).
  Neu geplant bei jeder Änderung des Blocks und bei jedem Timer-Wechsel; startet vorher ein Timer
  oder wird der Block erledigt, entfällt sie (auch eine schon zugestellte).

## Widget v2 – Oberfläche

Umsetzung in `TaktWidget/` auf Grundlage der Datenbasis oben. Grundsätze bleiben: ein Blick, eine
Aussage; keine Sekunden; ruhig; Projektfarbe als einziger Akzent; Hell/Dunkel.

### Konfiguration pro Widget
- `AppIntentConfiguration` mit `TaktWidgetConfigurationIntent` („Widget bearbeiten“): **Stil**
  (Standard/Schlicht/Farbfläche/Ring; „Standard“ = `SharedSettings.widgetStyle`, bei jedem Laden neu
  gelesen) und **Projekt** (optional, `ProjectEntity`; vorgeschlagen werden aktive Projekte, ein schon
  gewähltes archiviertes wird weiter aufgelöst; leer = alle Projekte).
- `kind` unverändert (`dev.eremiya.takt.widget`): vorhandene Widgets laufen mit den Standardwerten
  weiter. chronod übernimmt die neue Beschreibung erst, wenn es die Erweiterung als geändert erkennt;
  für Updates deshalb `CFBundleVersion` erhöhen.
- Größen: klein, mittel, groß (macOS: 164 × 164, 344 × 164, 344 × 344 pt).

### Ein-Projekt-Widget
- Zeigt nur das gewählte Projekt. Läuft es: Lauf-Zustand ohne Wechselziele. Läuft ein anderes:
  Pause-Zustand mit „Läuft: anderes Projekt“ statt „Nichts läuft“ und Start-Zeile (Start wechselt).
- Tagessumme, Budget, geplanter Block und Tagesleiste beziehen sich nur auf das Projekt; im großen
  Widget entfällt die Projektliste. Gibt es das Projekt nicht mehr: „Projekt fehlt“.

### Lauf-Zustand (alle Stile)
- **Wechseln:** klein zwei Farbpunkte (14 pt) unten links, mittel/groß Spalte „Wechseln zu“
  (`switchTargets`, `StartTimerIntent`).
- **Nächster Schritt** eine Zeile `.caption` unter dem Projektnamen; im kleinen Widget nur, wenn er
  in die Höhe passt (`ViewThatFits`).
- **Pausenstrich:** 2 pt unter der Dauer, Laufzeit / `breakReminderMinutes` (gedeckelt, ab 100 % voll),
  Projektfarbe 60 %, auf der Farbfläche Weiß; nur mit eingeschalteter Pausenerinnerung.
- **Budget im Ring:** mit `runningBudget` zeigt der Ring den Verbrauch (live), ab 80 % `#F59E0B`,
  über 100 % `#EF4444` und voll; darunter „12:30 / 40 h“. In Schlicht/Farbfläche steht das Budget
  im mittleren/großen Widget als Zahl in der Fußzeile.
- **Tagessumme** überall „Heute h:mm“ (inkl. laufendem Anteil); im Pause-Zustand mittel/groß groß
  mit Überschrift „Heute“.
- Ab zehn Stunden wird die Dauer kleiner gesetzt, damit „12:34“ nie gekürzt wird.

### Geplanter Block
- Pause: Zeile „14:00 · Kundenportal“ (bzw. „morgen 09:00 · …“) mit Farbpunkt und ▶︎
  (`StartTimerIntent`); fällig (`isDue`): Grund in Projektfarbe 15 % und „Jetzt: Kundenportal“. Klein und
  mittel ersetzt sie die dritte Schnellstart-Zeile (das Projekt des Blocks erscheint dann nicht
  doppelt); im Ring-Stil klein trägt der Start-Knopf im Ring den Block. Fällig wird er zur Zeit über
  einen zusätzlichen Timeline-Eintrag.
- Lauf: mittel/groß dezent „Geplant 16:00 · Website“. Gehört der fällige Block zum laufenden
  Projekt, entfällt er.
- Großes Widget: in der Fußzeile, mit ×-Knopf (`ClearPlannedBlockIntent`).

### Großes Widget
- Oben die Karte wie im mittleren Widget (Farbfläche läuft als farbige Karte, der Widget-Grund
  bleibt neutral), darunter die **Tagesleiste** 8–19 Uhr (erweitert bei Einträgen außerhalb) mit
  farbigen Abschnitten, Jetzt-Marke und Stundenmarken, darunter **alle Projekte** in zwei Spalten
  (Farbpunkt, Name, heutige Zeit; das laufende farbig hinterlegt; höchstens 6 Felder mit Fußzeile,
  sonst 8; darüber „+N weitere“), unten geplanter Block und – solange ein Timer läuft – Budget und
  „Heute h:mm“ (in Pause steht die Tagessumme groß in der Karte).

### Feinschliff
- `.contentTransition(.numericText())` für alle Dauern; Pause ↔ läuft mit Überblendung
  (`.easeInOut(0.35)`), die Farbfläche blendet ein.
- Lange Projektnamen in der mittleren/großen Karte bis zu zwei Zeilen (`minimumScaleFactor(0.85)`),
  sonst eine Zeile mit „…“.
- Galerie-Vorschau (`placeholder`, `snapshot` mit `isPreview`): echte Projekte, das erste (bzw. das
  feste) läuft simuliert seit 1:24; ohne Projekte `WidgetSnapshot.placeholder`.
- Entsättigte Schreibtisch-Darstellung (`widgetRenderingMode` `.vibrant`/`.accented`): Farbfläche wird
  zu Schlicht, Farbpunkte mit Ring, Budget- und Glyphentexte in `.primary`, Akzente `widgetAccentable`.
- Alle Knöpfe mit Bedienungshilfe-Text („Wechseln zu …“, „Timer stoppen“, „Geplanten Block entfernen“ …).

## Erfassung v3 (Tags, freie Tage, Wochenziel, Schnelleingabe)

Datenbasis in `TaktCore`, App-Anbindung über `TaktStore`, Oberfläche siehe „Oberfläche“ am Ende des Abschnitts.

### Datenmodell (Migration `v4`)

| Feld/Tabelle | Typ | Bedeutung |
|---|---|---|
| `TimeEntry.tag` | `String?`, TEXT | eine freie Kennzeichnung je Eintrag („Meeting“, „Bugfix“, „Review“); `NULL` = ohne Tag |
| `dayOff` | Tabelle | `id` (UUID), `date` (TEXT `YYYY-MM-DD`, **UNIQUE**), `kind` (`vacation`/`sick`/`holiday`/`other`), `note?` |
| Index `timeEntry_tag` | `(tag, projectId, startedAt) WHERE tag IS NOT NULL` | für die Tag-Vorschläge |

- **Tag-Normalisierung** (`TimeEntry.normalizedTag`): getrimmt, führende `#` entfernt, höchstens
  40 Zeichen (gekürzt, nicht abgelehnt), leer → `nil`. Gilt in `addEntry`, `updateEntry`, `startTimer`.
- **Freier Tag** = Kalendertag als Text, damit Zeitzone/Sommerzeit keine Rolle spielen
  (`DayOff.key(for:calendar:)`, `startOfDay(calendar:)`). `DayOffKind.title`: Urlaub, Krank, Feiertag,
  Sonstiges; unbekannte Rohwerte werden beim Lesen zu `.other`.
- Migration löscht nichts; geprüft mit echter v3-Datenbank (Test + Sicherung `takt.sqlite.bak-v3`).

### Repository

- `tagSuggestions(projectId:prefix:limit: = 8)`: zuerst Tags des Projekts, dann alle übrigen, jeweils
  nach letzter Nutzung (`MAX(startedAt)`); Präfix ohne Rücksicht auf Groß-/Kleinschreibung und Akzente
  (führendes `#` ignoriert); Dubletten auch in anderer Schreibweise entfernt (die jüngste gewinnt).
- `daysOff(in:calendar:)`, `dayOff(date:calendar:)`, `setDayOff(date:kind:note:calendar:)` (ersetzt
  den Eintrag des Tages, ID bleibt), `removeDayOff(date:calendar:)`, `isDayOff(date:calendar:)`.
- `startTimer(projectId:tag:now:)`: Überladung mit Tag. Läuft das Projekt schon, bekommt der laufende
  Eintrag den Tag (nur wenn einer angegeben ist). `startTimer(projectId:now:)` bleibt unverändert.
- `stopTimer(at:nextStep:)`: Stopp mit ausdrücklichem Ende („Leerlauf abziehen“); `end < startedAt`
  → Ende = Start. `stopTimer(nextStep:now:)` ruft es mit `now` auf.
- **Notiz beim Stoppen:** ein leerer `nextStep` lässt eine schon am laufenden Eintrag stehende Notiz
  (z. B. aus der Schnelleingabe) stehen, statt sie zu löschen.
- `discardRunning()`: löscht den laufenden Eintrag ersatzlos (abgebrochene Pomodoro-Einheit).

### Berichte

- `ProjectReportRow.byTag: [TagReportRow]` (`tag` – `nil` = ohne Tag –, `duration` ungerundet,
  `entryCount`), nach Dauer absteigend, bei Gleichstand alphabetisch, „ohne Tag“ zuletzt. Tags werden
  genau wie gespeichert gruppiert.
- `Report.daysOff` (freie Tage im Zeitraum), `Report.workdays` = Montag–Freitag im Zeitraum ohne freie
  Tage (ein freier Samstag zählt nicht doppelt), `averagePerWorkday = total / workdays` (0 ohne).
  `activeDays`/`averagePerActiveDay` bleiben.
- `Report.goal: GoalProgress?` nur bei `.week` und Ziel > 0: `target`, `achieved` (abrechenbare,
  ungerundete Zeit), `adjustedTarget = target × workdays / 5`, `fraction = achieved / adjustedTarget`
  (ungedeckelt; ohne Arbeitstage 1), `remaining`. Ziel über
  `report(for:rounding:defaultHourlyRate:weeklyGoal:now:calendar:)`; `TaktStore.report` liest es
  standardmäßig aus den Einstellungen.

### Schnelleingabe (`QuickEntryParser`)

`parse(_:projects:now:calendar:) -> Result<QuickEntry, QuickEntryError>`, tolerant und deutsch:
`[Tag] <Projekt> [Tag] [Zeit] [Tag] [#Tag] [Notiz…]`, das Projekt darf auch hinter der Zeit stehen.

| Eingabe | Ergebnis |
|---|---|
| `Kundenportal 9:00-10:30 Review` | heute 09:00–10:30, Notiz „Review“ |
| `kunden 9-10:30 #meeting Standup` | Kundenportal, Tag „meeting“, Notiz „Standup“ |
| `Garten 14:00 bis 15:15`, `von 8 bis 9:45 Uhr`, `9.30 - 11 Uhr`, `9–11` | Spanne |
| `Steuer gestern 20:00-21:00`, `Mo 9-11 Kundenportal`, `19.10. 9-10 Garten` | anderer Tag |
| `Website 1h30`, `45m`, `90min`, `1,5h`, `1:30h`, `2 Std`, `1h 15m` | Dauer, Ende = jetzt |
| `Website` | Timer-Start jetzt (`isRunningStart`) |
| `Website seit 9:30`, `Website 9:30`, `ab 9`, `9 Uhr` | Timer-Start rückwirkend |

- **Projekt:** längster passender Wortanfang, der Rest wird Notiz. Trefferstufen: gleich > Namensanfang
  > Wortanfang > Teilwort > ein Tippfehler > Buchstabenfolge (die letzten beiden nur für ein Wort);
  Groß-/Kleinschreibung und Akzente egal. Zwei gleich gute → `.ambiguousProject`, keiner →
  `.unknownProject`.
- **Tage:** `heute`, `gestern`, `vorgestern`, Wochentage (`Mo`/`Montag` … = letzter solcher Tag,
  **heute eingeschlossen**), `19.10.`/`19.10.2026` (ohne Jahr nie in der Zukunft); am Anfang oder direkt
  vor/nach der Zeit. Ein Wort, das nur ein Tag sein könnte und sonst nichts übrig ließe, gilt als Projekt.
- **Über Mitternacht:** Ende ≤ Start → nächster Tag, wenn die Spanne dann < 12 h ist, sonst
  `.invalidTimeRange`. Ohne ausdrücklichen Tag und Ende nach „jetzt“ ist die letzte Nacht gemeint
  (`23-1` um 18 Uhr = gestern 23:00 bis heute 01:00).
- Zahlen ohne Doppelpunkt (`1.20`) sind nur in Spannen oder mit `Uhr`/`ab`/`seit`/`um` Uhrzeiten.
- Fehler: `.empty`, `.missingProject`, `.missingTime` (anderer Tag ohne Start und Ende),
  `.startInFuture` (bloßer Start nach jetzt), alle mit deutschem `errorDescription`.
- **Übernehmen** (`TaktStore.commit`): fertiger Eintrag → `addEntry` (Notiz als „Nächster Schritt“,
  Tag); Timer-Start → `startTimer(projectId:tag:now:)`, rückwirkend, wenn der Start mehr als eine
  Minute zurückliegt (ein laufender anderer Timer endet dann zu diesem Start); die Notiz wird am
  laufenden Eintrag gespeichert und beim Stoppen ohne Notiz beibehalten.

### Einstellungen

- `SharedSettings.weeklyGoalHours: Double?` (Schlüssel `weeklyGoalHours`, gültig 0 < h ≤ 168, sonst
  `nil`), `weeklyGoal(in:)` in Sekunden – für ein späteres Widget.
- `AppSettings.weeklyGoalHours` spiegelt bei jeder Änderung und beim Start dorthin und lädt die
  Widget-Timelines neu; `AppSettings.weeklyGoal` liefert Sekunden.

### Oberfläche

**Heute**
- **Schnelleingabe** (`TodayQuickEntry`) unter den Start-Kapseln, volle Breite, Fokus per **⌘N**
  (unsichtbarer Knopf; `File › New` ist in der App leer). Beim Tippen eine Vorschauzeile:
  „● Kundenportal · 09:00–10:30 · 1:30 · #meeting · Standup“ (anderer Tag davor: „gestern“,
  „Mo 19.10.“), bei Timer-Start „Startet jetzt: Kundenportal“ bzw. „Startet ab 09:30: …“ (erst ab
  einer Minute Abstand, wie `commit`), sonst `errorDescription` mit orangem Hinweiszeichen.
  `ambiguousProject`: Kandidaten als Kapseln; Klick ersetzt die passende Wortfolge (bis drei Wörter)
  durch den vollen Projektnamen. **Enter** → `TaktStore.commit`; Erfolg leert das Feld und zeigt
  2,5 s „Eingetragen: …“/„Gestartet: …“, Misserfolg den Fehler orange (statt Hinweisfenster).
  **Esc** leert, ein zweites Esc gibt den Fokus ab. Ohne Projekte ausgeblendet.
- **Tags:** Kapsel (`TagCapsule`, `.caption2`, `.fill.quaternary`) hinter dem Projektnamen jeder
  Eintragszeile; die Farbkarte zeigt „seit 14:32 · Business · #Review“.
- **Stopp-Popover:** zusätzlich „Tag“, vorbelegt mit dem Tag des laufenden Eintrags, darunter
  Vorschläge (`TagSuggestionChips`). Geändertes Tag wird vor dem Stoppen per `updateEntry` am
  laufenden Eintrag gesichert, dann `stop(nextStep:)` (der Store kennt kein Stoppen mit Tag).
- **„Heute frei …“** oben rechts in der Pausenkarte (nur wenn nichts läuft); ist heute frei:
  „Heute frei: Urlaub“. Öffnet das Sheet „Freie Tage“ mit heute vorausgewählt.

**Eintrag bearbeiten:** Feld „Tag“, darunter klickbare Vorschläge aus
`tagSuggestions(projectId:prefix:)` (zuerst des gewählten Projekts). Gespeichert wird ab dem
Entwurf, damit `isBillable` erhalten bleibt (vorher ging es beim Sichern verloren).

**Freie Tage** (`DaysOffSheet`/`DaysOffContent`): Monatsraster Mo–So mit Blättern. Klick auf einen
Tag markiert ihn mit der zuletzt gewählten Art (Standard Urlaub); Klick auf einen freien Tag wählt
ihn, ein erneuter Klick entfernt die Markierung. Darunter Art (Segment: Urlaub/Krank/Feiertag/
Sonstiges, sofort gesichert) und Notiz (gesichert bei Enter, Tageswechsel oder „Fertig“). Farben je
Art (Türkis, Pink, Orange, Grau) nur hier.

**Berichte**
- Kopfzeile: „Freie Tage …“ (bei knapper Breite nur das Sonnen-Symbol) öffnet das Sheet für den
  Monat des Zeitraums (enthält er heute: den aktuellen).
- **Wochenziel** (nur wenn `report.goal != nil`): schmale Zeile unter den Kennzahlen
  „Wochenziel 24:26 von 32:00 (4 Arbeitstage) · noch 7:34 · 76 %“ mit Balken in der Akzentfarbe,
  ab 100 % grün mit Häkchen. Ziel aus `AppSettings.weeklyGoal`, Neuladen bei Änderung.
- **Diagramm:** freie Tage als schraffierte graue Spalte hinter den Balken (oben die Art, wenn die
  Spalte breit genug ist), im Hinweis „Mittwoch, 21. Okt. · Urlaub“. Nur bei Tages-Balken.
- **Fokus-Zeile:** „n Wechsel · längster Block · 4 Arbeitstage (1 frei) · Ø 7:05 pro Arbeitstag“;
  beim einzelnen Tag ohne Ø, an freien Tagen „frei: Urlaub“, am Wochenende „kein Arbeitstag“.
  Ein leerer freier Tag zeigt „Freier Tag · Urlaub“ samt Notiz.
- **Projektzeile aufgeklappt:** zuerst „nach Tag“ (nur wenn es Tags gibt): je Tag Balken in
  Projektfarbe mit Dauer, Anteil und Zahl der Einträge, „ohne Tag“ grau und immer zuletzt; darunter
  die Einträge mit Tag-Kapsel vor der Notiz.
- **CSV:** keine Spalte „Tag“ – `CSVExport.entries` liefert sie (noch) nicht; Ergänzung gehört in
  TaktCore (`entryHeader` + Feld hinter „Notiz“).

**Einstellungen › Abrechnung:** „Wochenziel (abrechenbare Stunden)“, leer = kein Ziel, Komma oder
Punkt, gültig über 0 bis 168 (`SharedSettings.validWeeklyGoalHours`), Hinweis „Passt sich freien
Tagen an: bei 4 Arbeitstagen gelten … h“.

## Fokus v2 (Leerlauf, Pomodoro) – Einstellungen

Einstellungen und Datenbasis; die Logik steht im folgenden Abschnitt „Fokus v2 – Leerlauf und
Pomodoro“.

| `AppSettings` | Standard | Bereich | Bedeutung |
|---|---|---|---|
| `idleDetectionEnabled` | an | | bei laufendem Timer nach Leerlauf fragen |
| `idleMinutes` | 10 | 1–120 | Minuten ohne Eingabe bis Leerlauf |
| `pomodoroEnabled` | aus | | Pomodoro-Modus |
| `pomodoroWorkMinutes` | 50 | 5–180 | Arbeitseinheit |
| `pomodoroBreakMinutes` | 10 | 1–60 | kurze Pause |
| `pomodoroLongBreakMinutes` | 20 | 1–120 | lange Pause |
| `pomodoroCyclesBeforeLongBreak` | 4 | 1–12 | Einheiten bis zur langen Pause |
| `pomodoroAutoStopTimer` | an | | Timer am Ende einer Einheit stoppen |

Werte außerhalb des Bereichs (z. B. per `defaults write`) fallen beim Start auf den Standard zurück.

Bausteine im Store: `stop(at:nextStep:)` für „Leerlauf abziehen“ (Ende = Beginn des Leerlaufs),
`discardRunning()` für eine abgebrochene Einheit, `start(projectId:tag:)`.

## Fokus v2 – Leerlauf und Pomodoro

### Leerlauf-Erkennung (`Takt/Focus/IdleDetector.swift`)
- Aktiv nur bei laufendem Timer und `idleDetectionEnabled`. Alle 30 s
  `CGEventSource.secondsSinceLastEventType(.combinedSessionState, kCGAnyInputEventType)`; ab
  `idleMinutes` ohne Eingabe gilt der Zeitraum als Leerlauf, Beginn = jetzt − Leerlauf.
- Ruhezustand (`NSWorkspace.willSleep`/`didWake`) und Bildschirmsperre
  (`com.apple.screenIsLocked`/`screenIsUnlocked`) zählen als Leerlauf ab der letzten Eingabe davor;
  Eingaben am Sperrbildschirm gelten nicht als Rückkehr.
- Während eines Leerlaufs wird alle 2 s geprüft. Rückkehr = letzte Eingabe < 5 s her. Nachgefragt
  wird nur, wenn derselbe Eintrag noch läuft und der Leerlauf innerhalb des Eintrags mindestens
  `idleMinutes` lang war.
- App aktiv → `NSAlert` (Sheet am Hauptfenster, sonst app-modal; andere Apps bleiben bedienbar):
  „Du warst 23 Minuten inaktiv (seit 14:32).“ / „Was soll mit der Zeit passieren? …“
  Knöpfe **Abziehen** (Standard), **Behalten** (Esc), **Bei Leerlauf stoppen**.
- App nicht aktiv → Mitteilung „23 Min Leerlauf erkannt – klicken zum Entscheiden“ (Kategorie
  `dev.eremiya.takt.idle`, Aktionen „Abziehen“/„Behalten“); Klick darauf holt Takt nach vorn und
  zeigt den Alert. Verwerfen = Behalten.
- **Abziehen:** Lücke < 2 min → nichts. Sonst `stop(at: idleStart)` und sofort Neustart mit
  demselben Projekt und Tag (`start(projectId:tag:)`); der neue Eintrag beginnt mit dem Ende des
  Leerlaufs (nicht erst mit der Antwort) und übernimmt eine abweichende Abrechenbarkeit → zwei
  Einträge mit Lücke. Begann der Leerlauf schon mit dem Eintrag, wird nur dessen Beginn verschoben.
- **Bei Leerlauf stoppen:** `stop(at: idleStart)`; deckt der Leerlauf den ganzen Eintrag ab,
  `discardRunning()`.
- Wurde der Timer inzwischen anderswo gestoppt oder gewechselt, bewirkt eine späte Antwort nichts.

### Pomodoro (`Takt/Focus/PomodoroController.swift`)
- Nur mit `pomodoroEnabled`. Zyklus: Arbeit (`pomodoroWorkMinutes`) → kurze Pause → … nach
  `pomodoroCyclesBeforeLongBreak` Einheiten lange Pause, danach wieder Einheit 1.
- Eine Arbeitseinheit beginnt mit dem Timer-Start (nichts läuft → läuft; Starts aus dem Widget
  zählen ab Beginn des Eintrags, wenn er höchstens 5 min zurückliegt). Projektwechsel setzen sie
  nicht zurück. Ein Stopp vor Ablauf bricht die Einheit ab (zählt nicht). Ein Timer-Start während
  der Pause beendet die Pause und beginnt die nächste Einheit.
- Ende der Arbeit: Mitteilung „Pomodoro: Pause (10 Min)“ bzw. „Pomodoro: lange Pause (20 Min)“ mit
  Ton. Mit `pomodoroAutoStopTimer` wird der Timer gestoppt (Musik pausiert dann wie bei jedem
  Stopp); kam das Ende verspätet (Ruhezustand), endet der Eintrag zum eigentlichen Ende.
  Ohne automatischen Stopp nur der Hinweis; der Timer läuft durch die Pause.
- Ende der Pause: ohne laufenden Timer Mitteilung „Pause vorbei – weiter mit <Projekt>?“
  (Kategorie `dev.eremiya.takt.pomodoro-break-over`, Aktion „Weiter“ startet `lastUsedProject`)
  und 2 s die Einblendung des Kurzbefehls. Läuft der Timer noch, beginnt die nächste Einheit sofort
  („Pause vorbei“).
- Ersetzt die Pausenerinnerung: `BreakReminder` plant bei `pomodoroEnabled` nichts; Ein- und
  Ausschalten plant sie neu.
- Menüleiste: Zusatz „· 🍅 23:00“ (Restzeit der Arbeit) bzw. „· Pause 07:00“; ohne laufenden Timer
  in der Pause Tassen-Symbol + „Pause 07:00“. Restzeit in angefangenen Minuten, Aktualisierung
  jeweils zur vollen Restminute.
- Popover: unter der Karte „Pomodoro 2/4 · Arbeit · noch 23 min“ mit „Phase überspringen“ (Arbeit
  endet sofort wie regulär, Pause endet ohne Mitteilung).
- Zustand nur im Speicher; ein App-Neustart beginnt mit Einheit 1 (läuft beim Start ein Timer,
  beginnt die Einheit mit dessen Beginn, sofern der innerhalb einer Einheitslänge liegt).

### Mitteilungen
- `NotificationCategories.register()` registriert beim App-Start alle Kategorien auf einmal
  (Pausenerinnerung, geplanter Block, vergessener Timer, Leerlauf, Pomodoro) – kein Lesen-und-Ergänzen
  mehr in einzelnen Klassen, damit keine Kategorie verloren geht.
- Antworten laufen weiter über das Delegate von `BreakReminder`, das Mitteilungen von
  `ForgottenTimerGuard`, `IdleDetector` und `PomodoroController` an diese weiterreicht.
- Log-Kategorie `focus`.

## v5 – Datenbasis: Pomodoro-Widget, Jahr, Budget-Warnungen, Kalender, Aktivität

Datenbasis in `TaktCore` und Anbindung im Store für sechs Folgefunktionen: Pomodoro im Widget,
Jahresberichte, Budget-Warnungen, Schnelleingabe überall, Kalender-Anbindung (EventKit) und
Aktivitäts-Erkennung. Oberflächen folgen; in den Einstellungen stehen „Kalender“ und „Aktivität“
vorerst als Platzhalter (Reihenfolge Allgemein · Musik · Fokus · Widget · Abrechnung · Kalender ·
Aktivität, Fenster 560 pt breit).

### Datenmodell (Migration `v5`)

| Feld/Tabelle | Typ | Bedeutung |
|---|---|---|
| `TimeEntry.updatedAt` | `Date`, REAL, NOT NULL | letzte Änderung; Altbestände = `startedAt`. Gesetzt von `addEntry`, `updateEntry`, `startTimer` (neuer Eintrag, Tag am laufenden, beendeter vorheriger) und `stopTimer` – jeweils mit optionalem `now:` |
| `calendarEventLink` | Tabelle | `entryId` (PK, FK → `timeEntry`, `ON DELETE CASCADE`), `eventIdentifier`, `calendarIdentifier`, `updatedAt` (letzte Spiegelung) |
| `calendarRule` | Tabelle | `id`, `kind` (`calendarName`/`titleContains`/`attendeeDomain`), `pattern`, `projectId` (FK, CASCADE), `sortOrder`, `createdAt` |
| `activityRule` | Tabelle | `id`, `kind` (`bundleID`/`windowTitleContains`/`repoPath`), `pattern`, `projectId` (FK, CASCADE), `sortOrder`, `createdAt` |
| `activitySample` | Tabelle | `id`, `startedAt`, `endedAt`, `bundleID`, `windowTitle?`, `repoPath?`, `projectId?` (FK, `ON DELETE SET NULL`) |

Migration löscht nichts; geprüft mit Test (v4-Datenbank mit Daten) und an der echten Datenbank
(Sicherung `takt.sqlite.bak-v4` per `sqlite3 .backup`).

### Pomodoro im Widget (`SharedSettings`)

- `PomodoroState` (`enabled`, `phase` – `work`/`shortBreak`/`longBreak`/`idle`, unbekannt → `idle` –,
  `phaseEndsAt?`, `cycle`, `cyclesBeforeLongBreak`, `updatedAt`) als JSON unter `pomodoroState` in der
  App-Group-Suite: `SharedSettings.pomodoro` (get/set), `pomodoro(in:)`, `setPomodoro(_:in:)`
  (`nil` entfernt), `clearPomodoro(in:)`. Hilfen: `remaining(at:)`, `isActive(at:)`, `Phase.isBreak`/`title`.
- Schreiben ist Sache des `PomodoroController` (bei jedem Phasenwechsel); `AppSettings` löscht den
  Zustand, wenn der Modus aus ist (auch beim Start).
- `WidgetSnapshot.pomodoro` nur bei `enabled`; `placeholder` zeigt Einheit 2/4, Arbeit, noch 23 min.

### Jahresbericht (`Reports.swift`)

`yearReport(year:rounding:defaultHourlyRate:now:calendar:) -> YearReport` – eine Leseabfrage für Jahr
und Vorjahr, gerechnet mit derselben Logik wie `report(for:)`:
- `months`: genau 12 `MonthBucket` (1. des Monats, `total`, `billable`, `roundedBillable`, `business`,
  `personal`, `amount`, `activeDays`), auch leere Monate.
- `byProject` = Zeilen des ganzen Jahres; `byClient: [ClientRow]` (`client` getrimmt, gleiche Namen in
  anderer Schreibweise zusammengefasst – die Schreibweise des größten Projekts gewinnt; `nil` = ohne
  Kunde), sortiert nach Betrag, dann Dauer.
- `tagShares`: die 8 größten Tags, danach „Sonstige“ (`isOther`) und „ohne Tag“ (`tag == nil`); Anteile
  an `total`, zusammen 1. `TagShare.title` liefert den Anzeigenamen.
- Summen (`total`, `billable`, `amount`, `business`, `personal`, `activeDays`, `averagePerActiveDay`)
  aus dem Jahreszeitraum; `previousYearTotal`/`previousYearAmount` mit gleicher Rundung.
- Rundung je Eintrag nach dem Zuschneiden: Ein Eintrag über eine Monatsgrenze wird in den Monaten je
  Teil gerundet – die Summe der Monatsbeträge kann um Cent von `amount` abweichen.

### Budget-Warnungen

`budgetUsages(now:) -> [BudgetUsage]` (`project`, `used`, `budget`, `fraction`, `remaining`): alle
aktiven Projekte mit Budget > 0 in Projektreihenfolge, eine Abfrage, laufender Eintrag bis `now`.
Schalter `AppSettings.budgetWarningsEnabled` (Standard an); Schwellen (80 %/100 %) legt die Oberfläche fest.

### Kalender

- Verknüpfungen: `calendarLink(entryId:)`, `calendarLinks()`, `setCalendarLink(_:)` (ersetzt; unbekannter
  Eintrag → `entryNotFound`), `removeCalendarLink(entryId:)`.
- `entriesNeedingMirror(since:minimumDuration:)`: abgeschlossene Einträge mit Ende ≥ `since` und Dauer
  ≥ Mindestdauer, ohne Verknüpfung **oder** mit `link.updatedAt < entry.updatedAt`; nach Beginn.
  Nach dem Spiegeln setzt die App die Verknüpfung mit `updatedAt = jetzt`.
- `removeOrphanLinks()` entfernt Verknüpfungen ohne Eintrag (Altlasten) oder zu laufenden Einträgen und
  gibt sie zurück. **Achtung:** Beim Löschen eines Eintrags verschwindet die Verknüpfung per CASCADE –
  die App muss das Kalenderereignis vorher über `calendarLink(entryId:)` ermitteln und löschen.
- Regeln: `calendarRules()` (unbekannte Arten werden übersprungen), `addCalendarRule(kind:pattern:projectId:now:)`
  (hängt hinten an, Muster getrimmt, leer → `TaktError.emptyPattern`), `saveCalendarRule`,
  `deleteCalendarRule(id:)`, `reorderCalendarRules(ids:)`.
- `matchCalendarRule(calendarName:title:attendeeDomains:)`: erste passende Regel nach `sortOrder`, deren
  Projekt nicht archiviert ist. Vergleiche ohne Groß-/Kleinschreibung und Akzente: Kalendername
  gleich, Titel enthält, Domain gleich oder Subdomain (`anna@mail.acme.de` passt zu `@acme.de`, nicht
  `notacme.de`); Teilnehmer dürfen als Adresse oder Domain kommen.

### Aktivität

- Regeln wie beim Kalender: `activityRules()`, `addActivityRule`, `saveActivityRule`, `deleteActivityRule`,
  `reorderActivityRules`, `matchActivityRule(bundleID:windowTitle:repoPath:)` – Bundle-ID gleich, Titel
  enthält, Repository gleich oder darunter (`/dev/takt` passt zu `/dev/takt/TaktCore`, nicht zu
  `/dev/takt2`). Pfade normalisiert (`ActivityRule.normalizedPath`: `~` und `file://` aufgelöst, `.`/`..`
  und `/` am Ende entfernt, klein geschrieben, ohne Symlink-Auflösung).
- Proben: `addActivitySample(_:resolveProject: = true)` trimmt Texte, ermittelt das Projekt per Regel
  (ein unbekanntes Projekt wird `nil`) und löscht in derselben Transaktion Proben, die mehr als 30 Tage
  vor ihr enden (`activitySampleRetention`); `activitySamples(in:)`, `pruneActivitySamples(olderThan:)`.

### Einstellungen (`AppSettings`)

| Schlüssel | Standard | Bereich | Bedeutung |
|---|---|---|---|
| `calendarShowEvents` | aus | | Termine in „Heute“ (an erst nach Berechtigung) |
| `calendarVisibleIDs` | `[]` | | angezeigte Kalender, leer = alle |
| `calendarMirrorEnabled` | aus | | Einträge in einen Kalender spiegeln |
| `calendarMirrorCalendarID` | `nil` | | Zielkalender |
| `calendarMirrorMinimumMinutes` | 5 | 1–240 | kürzere Einträge nicht spiegeln |
| `activitySuggestionsEnabled` | aus | | Projektvorschläge aus Aktivität |
| `activityMismatchMinutes` | 10 | 1–120 | so lange muss die Aktivität abweichen |
| `activityAutoStartEnabled` | aus | | ohne Timer automatisch starten |
| `budgetWarningsEnabled` | an | | Budget-Warnungen |
| `quickEntryHotKeyEnabled` | an | | globaler Kurzbefehl Schnelleingabe |
| `quickEntryHotKeyKeyCode` | 45 (N) | 0–127 | Taste |
| `quickEntryHotKeyModifiers` | ⌃⌥⌘ | | Modifikatoren (0 → Standard) |
| `quickEntryInMenuBar` | an | | Schnelleingabe im Menüleisten-Popover |

### Store (`TaktStore`)

- Neu gelesen in `refresh()`: `calendarRules`, `activityRules`.
- Lesen: `yearReport(year:rounding:defaultHourlyRate:now:)`, `budgetUsages(now:)`, `calendarLink(entryId:)`,
  `entriesNeedingMirror(since:minimumDuration:)`, `matchCalendarRule(…)`, `matchActivityRule(…)`,
  `activitySamples(in:)`.
- Schreiben mit `refresh()` und Darwin-Notification, aber ohne Widget-Reload: Kalender-Verknüpfungen
  (`setCalendarLink`, `removeCalendarLink`, `removeOrphanCalendarLinks`) und Regeln (`add…Rule`,
  `save…Rule`, `delete…Rule`, `reorder…Rules(fromOffsets:toOffset:)`).
- Proben (`addActivitySample`, `pruneActivitySamples`) ganz still: kein `refresh()`, keine
  Benachrichtigung, kein Widget-Reload.
