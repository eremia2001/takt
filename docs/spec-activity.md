# Aktivitäts-Erkennung

Takt erkennt die vorderste App, den Fenstertitel und das Git-Repository, ordnet die Arbeit einem
Projekt zu und meldet sich, wenn der laufende Timer nicht dazu passt (oder keiner läuft).
Datenbasis (Regeln, Proben) siehe `SPEC.md` → v5 → Aktivität.

## Dateien

| Datei | Inhalt |
|---|---|
| `Takt/Activity/ActivityHeuristics.swift` | Reine Logik ohne AppKit: App-Familien, Ignorierliste, Titel zerlegen, Repo finden (`detectRepo`), Projekt raten (`guessProject`), `RepoIndex` |
| `Takt/Activity/ActivityProbe.swift` | Accessibility: Titel und Dokument des fokussierten Fensters, Freigabe prüfen/anfragen; `ActivityAppNames` |
| `Takt/Activity/ActivityMonitor.swift` | `@MainActor @Observable`: Takt, Abschnitte, Speichern, Abgleich, Mitteilungen, Antworten |
| `Takt/Settings/Sections/ActivitySettingsSection.swift` | Reiter „Aktivität“ |

## Beobachten

- Nur bei `activitySuggestionsEnabled` (per `observeContinuously` verfolgt; Aus beendet und speichert
  den laufenden Abschnitt).
- Alle 15 s und bei `NSWorkspace.didActivateApplicationNotification`: vorderste App
  (`bundleIdentifier`, `localizedName`). Mit `AXIsProcessTrusted()` zusätzlich
  `kAXFocusedWindowAttribute` (ersatzweise `kAXMainWindowAttribute`) → `kAXTitleAttribute` und
  `kAXDocumentAttribute`; Zeitlimit 0,5 s je Abfrage, abseits des Main-Threads. Ohne Freigabe nur
  die Bundle-ID.
- **Leerlauf:** ≥ 5 min ohne Eingabe (`IdleDetector.secondsSinceLastInput()`) oder gesperrter
  Bildschirm → Abschnitt endet bei der letzten Eingabe, nichts wird bewertet.
- **Ignorierte Apps** (Finder, Systemeinstellungen, Takt, Musik, Spotify, Dock, Spotlight,
  Mitteilungszentrale, Anmeldefenster, Bildschirmschoner …): werden nicht gespeichert und
  unterbrechen nichts – der laufende Abschnitt bleibt offen, verlängert sich aber nicht. Browser
  sind **nicht** ignoriert.

## Repository finden

Reihenfolge, erster Treffer gewinnt; Ergebnis normalisiert (`~` aufgelöst, `.`/`..` und `/` am
Ende entfernt, Groß-/Kleinschreibung bleibt):

1. `kAXDocumentAttribute` (Xcode: Datei, Terminal: Arbeitsordner) → aufwärts bis zum ersten Ordner
   mit `.git` (Ordner oder Datei).
2. Pfade im Titel: Teile, die mit `~/` oder `/` beginnen, auch nach `user@host: ` oder in eckigen
   Klammern (JetBrains `takt [~/dev/takt]`) → ebenso aufwärts.
3. Titelteile als Ordnername gegen den `RepoIndex` (Ordner mit `.git` direkt unter `~/dev`,
   außerdem `~/Developer`, `~/Projects`, `~/code`; alle 5 min neu eingelesen): erst Name gleich
   (ohne Groß-/Kleinschreibung), dann gefaltet gleich (`EventBuster App` ↔ `eventbuster-app`, nur
   eindeutige).

Das Benutzerverzeichnis und `/` gelten nie als Repository (Dotfiles), hochgelaufen wird höchstens
bis dorthin.

**Titel zerlegen:** Trennzeichen ` — `, ` – `, ` - `, ` | `. Entfernt werden „●“-Markierungen,
`[SSH: …]` u. ä., Klammerzusätze am Ende (`(Workspace)`, `(zsh)`), Fenstergrößen (`80×24`),
Shell-/Prozessnamen (`-zsh`, `claude`, `node` …) und App-Namen (`Visual Studio Code`, `Cursor` …).

| Familie | Apps | Reihenfolge der Namenskandidaten |
|---|---|---|
| Datei zuerst | VS Code, Cursor, Windsurf, VSCodium, Sublime | von hinten („datei — repo“) |
| Projekt zuerst | Xcode, Zed, JetBrains, Android Studio, Nova | von vorn („repo — datei“) |
| Terminal | Terminal, iTerm, Ghostty, Warp, kitty, Alacritty, WezTerm | von vorn |
| Browser | Safari, Chrome, Firefox, Arc, Brave, Edge … | keine (nur Regeln) |
| Sonstige | alle anderen | nur Teile nach dem ersten Trennzeichen |

## Projekt zuordnen

1. Erste passende `ActivityRule` aus `store.activityRules` (im Speicher, gleiche Logik wie
   `matchActivityRule`; Regeln archivierter Projekte übersprungen).
2. Ohne Regel, aber mit Repository: Repo-Ordnername ≈ Projektname (`ActivityHeuristics.fold`:
   klein, ohne Akzente, nur Buchstaben/Ziffern). Gleichheit, sonst Teiltext in beide Richtungen
   (kürzerer Name ≥ 4 Zeichen); mehrere Treffer → längster Projektname.

Das so ermittelte Projekt steht in `ActivitySample.projectId` (auch das geratene).

## Abschnitte speichern

- Gleiche Aktivität = gleiche Bundle-ID + gleiches Repository (Titel darf wechseln, der letzte wird
  behalten) bzw. ohne Repository gleicher Titel – und gleiches Projekt.
- Gleich und Lücke ≤ 45 s → `endedAt` verlängern (nur im Speicher). Wechsel → alter Abschnitt
  endet jetzt (bei Lücke ≤ 45 s) und wird mit `store.addActivitySample` gespeichert.
- Gespeichert wird außerdem bei Leerlauf, Sperre, Ruhezustand, Benutzerwechsel, Beenden, Ausschalten
  und spätestens nach 30 min (Zwischenstand, nahtlos fortgesetzt). Abschnitte < 5 s entfallen.
- Einmal täglich `pruneActivitySamples(olderThan: jetzt − 30 Tage)` (zusätzlich zur Bereinigung in
  `addActivitySample`).
- Im Speicher bleiben die abgeschlossenen Abschnitte der letzten 3 h (beim Einschalten aus der
  Datenbank geladen).

## Abgleich

Nach jeder Beobachtung, Zeitraum = letzte `activityMismatchMinutes` Minuten, frühestens ab Start des
laufenden Timers bzw. ohne Timer ab dem letzten Stopp heute. Projekt Y = Projekt mit der meisten
Zeit im Zeitraum; es muss **≥ 70 % der Zeitraumlänge** ausmachen und darf nicht archiviert sein.

| Lage | Mitteilung | Aktionen |
|---|---|---|
| Timer auf X ≠ Y | „Passt der Timer?“ – „Timer läuft auf Website, du arbeitest aber seit 12 Min in eventbuster-app (EventBuster)“ | Wechseln / Starten → startet Y; Ignorieren → (X, Y) 2 h still |
| kein Timer | „Timer starten?“ – „Du arbeitest seit 12 Min in eventbuster-app (EventBuster) – Timer starten?“ | Starten / Wechseln → startet Y; Ignorieren → (–, Y) 2 h still |
| kein Timer, `activityAutoStartEnabled` | startet Y sofort; „Timer gestartet: EventBuster“ (ohne Aktionen) | – |

- Höchstens einmal je (X, Y, Stunde); in einer laufenden Pomodoro-Pause kein Startvorschlag.
- „seit … Min“: Zeit in Y rückwärts ab jetzt, bis eine Lücke > 5 min oder ein anderes Projekt
  > 2 min dazwischenkommt (mindestens die Zeit im Zeitraum). Ort: Repo-Ordnername, sonst App-Name;
  gleicher Name wie das Projekt → nur das Projekt.
- Läuft der Timer inzwischen auf Y, wird die zugestellte Nachfrage entfernt.
- Kennung `dev.eremiya.takt.activity` (neue ersetzt alte), Kategorie
  `NotificationCategories.Activity`. Antworten: `BreakReminder.addResponseHandler` – der Handler
  nimmt alles mit `categoryIdentifier == Activity.category` (`true`) und arbeitet auf dem MainActor.
- Log: `Logger(subsystem: "dev.eremiya.takt", category: "activity")`; Titel, Pfade und
  Projektnamen `.private`.

## Einstellungen (Reiter „Aktivität“)

- **Aktivität:** Schalter „Projektvorschläge aus Aktivität“; Bedienungshilfen-Status mit „Freigeben …“
  (`AXIsProcessTrustedWithOptions` mit Abfrage + Systemeinstellungen → Bedienungshilfen) und Hinweis,
  was ohne Freigabe geht; Stepper „Nachfragen nach N Minuten“ (1–120); Schalter „Automatisch starten“.
- **Regeln:** je Zeile ▲/▼ (Reihenfolge), Art (App / Fenstertitel enthält / Repo-Pfad), Muster
  (gespeichert bei Enter oder beim Verlassen; leer → alter Wert), Projekt, − (löschen). „+“ öffnet
  ein Popover mit Art, Muster (Hilfe: laufende App wählen bzw. Ordner wählen …) und Projekt.
- **Zuletzt erkannt:** die letzten 10 Abschnitte (24 h, laufender zuerst, „läuft“): Zeit, Dauer, App,
  Repository bzw. Titel, erkanntes Projekt; „Regel daraus“ → Popover mit Repo-Pfad (sonst App) und
  Projekt-Picker. Aktualisiert alle 3 s, solange der Reiter sichtbar ist.
- Fußzeile Datenschutz: alles lokal, 30 Tage.
- `ActivityMonitor` ist optional in der Umgebung (`@Environment(ActivityMonitor.self) … ActivityMonitor?`);
  ohne ihn fehlt nur der laufende Abschnitt.

## Grenzen

- Accessibility liefert nur Fenster des aktuellen Space; Vollbild-Apps auf anderen Spaces sind
  unsichtbar, bis sie vorne sind (dann aber normal lesbar).
- Die Kategorie `Activity` hat alle drei Aktionen; macOS zeigt daher in beiden Nachfragen „Wechseln“
  und „Starten“ (beide starten Y).
- Der laufende Abschnitt liegt bis zum Speichern nur im Speicher; bei einem Absturz gehen höchstens
  30 min verloren.
