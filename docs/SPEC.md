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
Stundensätze/Rechnungen, geplanter Block im Widget, Schätzung vs. Ist, Aufgaben, iCloud/iPhone,
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
