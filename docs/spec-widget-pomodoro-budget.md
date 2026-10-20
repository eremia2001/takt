# Pomodoro im Widget und Budget-Warnungen

Baut auf „v5 – Datenbasis“ in `SPEC.md` auf (`PomodoroState`, `SharedSettings.pomodoro`,
`WidgetSnapshot.pomodoro`, `budgetUsages(now:)`, `AppSettings.budgetWarningsEnabled`).

## Pomodoro-Zustand schreiben (`Takt/Focus/PomodoroController.swift`)

- `publishWidgetState()` spiegelt den Zustand nach `SharedSettings.pomodoro` und ruft
  `WidgetCenter.shared.reloadAllTimelines()` auf – **nur bei Änderung** (Vergleich mit dem zuletzt
  geschriebenen Zustand), damit die minütlichen Durchläufe das Widget nicht ständig neu laden.
- Aufgerufen in `restartLoop()` (dort läuft jeder Übergang durch: Start, Stopp/Abbruch, Phasenwechsel,
  Überspringen, geänderte Dauer, Aufwachen) und im Ein-/Ausschalt-Zweig von `sync` (auch App-Start).
- Ausgeschaltet: `SharedSettings.clearPomodoro()`.
- Felder: `enabled` true, `phase` (`work`/`shortBreak`/`longBreak`, bereit = `idle`), `phaseEndsAt`
  (`nil` bei bereit), `cycle` (gedeckelt auf `cyclesBeforeLongBreak`), `cyclesBeforeLongBreak`.
- **`updatedAt` = Beginn der Phase** (bereit: Zeitpunkt, seit dem es bereit ist). Abweichung von der
  Feldbeschreibung „Zeitpunkt des Schreibens“: Nur so kann das Widget den verstrichenen Anteil
  berechnen – die Phasendauern liegen nicht in der App-Group-Suite.

## Widget (`TaktWidget/`)

### Daten (`Provider.swift`)
- `TaktEntry.pomodoro: PomodoroDisplay?` – nur bei `enabled`, Phase ≠ `idle` und Ende nach `date`.
  `TaktEntry.pomodoroBreak` – dasselbe, nur in einer Pause.
- `PomodoroDisplay`: `remaining`, `remainingMinutes` (angefangene Minuten wie Menüleiste/Popover),
  `fraction` = (date − updatedAt) / (phaseEndsAt − updatedAt), Texte `label` („🍅 23 min“ /
  „Pause 7 min“), `clock` („7:00“, ab 60 min „1:05:00“), `cycleLabel` („Pomodoro 2/4“).
- **Timeline:** Läuft eine Phase, kommen zu den bisherigen Einträgen (Minutengrenzen der Laufzeit
  bzw. Pause-Zustand mit Neuladen nach 1 h/Mitternacht und Block-Beginn) die Grenzen der
  Restminuten (Ende − n min) und ein Eintrag **zum Phasenende**. Liegt das Phasenende im Horizont,
  endet die Timeline dort (`.atEnd`); die App schreibt die nächste Phase und lädt ohnehin neu.
  Zeitpunkte < 1 s auseinander werden zusammengefasst.

### Lauf-Zustand (alle Stile, alle Größen)
- `RunningProgressLine`: mit Pomodoro der **Pomodoro-Strich** (`PomodoroProgressBar`, 3 pt),
  sonst wie bisher der Pausenstrich aus `breakReminderMinutes`.
- Füllung = verstrichener Anteil der Phase. Arbeit in Projektfarbe (75 %), Pause neutral
  (`.secondary`); auf der Farbfläche Weiß (Pause blasser); entsättigt `.primary`.
- Mittel/groß: rechts `.caption2` „🍅 23 min“ bzw. „Pause 7 min“. Klein: ohne Beschriftung, davor
  🍅 (Arbeit) bzw. Tassen-Symbol (Pause).
- **Ring:** Der Ring zeigt die Phase (verstrichener Anteil; Arbeit Projektfarbe, Pause `.secondary`)
  statt Budget/Stunde; der Pausenstrich in der Mitte entfällt. Unter dem Ring
  „Pomodoro 2/4 · 🍅 23 min“ bzw. „Pomodoro 2/4 · Pause 7 min“. Klein ersetzt diese Zeile die
  Budget-Zeile (Höhe), mittel/groß steht das Budget darunter.

### Pause-Zustand mit Pomodoro-Pause (kein Timer)
- Schlicht/Farbfläche: „☕ Pause · noch 7 min“ unter „Nichts läuft“ (klein und in der Karte
  mittel/groß). Klein reicht die Höhe dann nur für zwei Schnellstart-Zeilen (Block zählt mit).
- Ring: neutraler Ring mit dem **Restanteil**, Mitte „Pause“ / „7:00“; die Tagessumme steht
  mittel/groß als „Heute h:mm“ unter dem Ring.
- Arbeitsphase ohne Timer (nur kurzzeitig möglich) zeigt nichts.

### Vorschauen
`WidgetSnapshot.previewPomodoroWork`, `.previewPomodoroBreakRunning`, `.previewPomodoroBreakIdle`
(`withPomodoro(_:)`, `previewPomodoro(_:elapsed:remaining:)`) in „Pomodoro“, „Pomodoro mittel“,
„Pomodoro groß“. Hinweis: `WidgetSnapshot.placeholder` setzt `updatedAt = now` – dort ist der
Strich leer (Anteil 0).

## Budget-Warnungen (`Takt/Focus/BudgetWatcher.swift`)

- `@MainActor @Observable final class BudgetWatcher(store:settings:defaults:)`.
- Prüft über `store.budgetUsages()` nach jeder Änderung von `store.running`, `store.budgetCompleted`,
  `store.projects` (= nach einem `refresh`, der etwas geändert hat, z. B. neuer Eintrag, geändertes
  Budget) und `settings.budgetWarningsEnabled`, sowie **minütlich, solange ein Timer läuft**.
- Schwellen 80 % und 100 % (`fraction >= 0.8` bzw. `>= 1`), je Projekt **einmal**: Merker
  `budgetWarned.<projectId>.<80|100>` in `UserDefaults.standard`. Fällt `fraction` unter die
  Schwelle, wird der Merker gelöscht (nach Budgeterhöhung meldet sie sich wieder).
- Werden beide Schwellen auf einmal erreicht, kommt nur die 100-%-Mitteilung (beide Merker gesetzt).
- Ausgeschaltet (`budgetWarningsEnabled == false`): keine Prüfung, Merker bleiben unverändert.
- Mitteilung (Kategorie `NotificationCategories.Budget.category`, Kennung
  `dev.eremiya.takt.budget.<projectId>` – „überschritten“ ersetzt die 80-%-Mitteilung, Ton):
  - Titel „Budget 80 %: Kundenportal“, Text „32:00 von 40 h verbraucht“
  - Titel „Budget überschritten: Kundenportal“, Text „41:10 von 40 h“
- Antwort: `BudgetWatcher.handleNotificationResponse(_:)` (für `BreakReminder.addResponseHandler`):
  passt `categoryIdentifier`, gibt `true` zurück; „Projekt öffnen“ oder Klick →
  `MenuBarController.showToday()` (`takt://today`, App nach vorn).
- Log-Kategorie `focus`.

## Verdrahtung (`Takt/TaktApp.swift`)

```swift
/// Budget-Warnungen (80 % / 100 %); lebt so lange wie die App.
@State private var budgetWatcher: BudgetWatcher

// in init(), nach `_pomodoroController = …`:
BreakReminder.addResponseHandler(BudgetWatcher.handleNotificationResponse)
_budgetWatcher = State(initialValue: BudgetWatcher(store: store, settings: settings))
```
