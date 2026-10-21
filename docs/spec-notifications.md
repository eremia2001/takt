# Mitteilungen

Alle Mitteilungsarten von Takt auf einen Blick: Reiter **Einstellungen › Mitteilungen**, ein Gate
vor jedem `UNUserNotificationCenter.add` und Ruhezeiten.

## Dateien

| Datei | Inhalt |
|---|---|
| `Takt/Focus/NotificationGate.swift` | `NotificationKind`, Protokoll `NotificationGateSettings`, `NotificationGate` (Schalter, Ruhezeiten, Wochenende) |
| `Takt/Focus/NotificationPermission.swift` | Systemstatus, Erlaubnis anfragen, Systemeinstellungen öffnen, Testmitteilung |
| `Takt/Focus/NotificationCategories.swift` | Kategorien; `deliverNow(identifier:content:kind:settings:)` prüft das Gate |
| `Takt/Settings/Sections/NotificationsSettingsSection.swift` | Reiter „Mitteilungen“ |
| `Takt/Views/SettingsView.swift` | `SettingsTab`, Reiterauswahl, Anbindung an `AppNavigator` |

## Einstellungen (`AppSettings`)

| Schlüssel | Standard | Bedeutung |
|---|---|---|
| `forgottenTimerEnabled` | an | Nachfrage bei vergessenem Timer (Alert und Mitteilung) |
| `activityNotificationsEnabled` | an | Mitteilungen der Aktivitäts-Erkennung; aus = Vorschläge/Auto-Start laufen weiter, nur ohne Mitteilung |
| `calendarMeetingHintEnabled` | an | In-App-Hinweis „Termin läuft“ in „Heute“ (keine Systemmitteilung) |
| `calendarPlannedBlockNotificationEnabled` | an | „Geplant: X um 14:00“ |
| `pomodoroNotificationsEnabled` | an | Pomodoro-Mitteilungen (die Einblendung am Bildschirm bleibt) |
| `pomodoroSoundEnabled` | an | Ton bei Pomodoro-Mitteilungen |
| `notificationsQuietHoursEnabled` | aus | Ruhezeiten |
| `quietHoursStart` | 1080 (18:00) | Minuten seit Mitternacht, 0–1439 |
| `quietHoursEnd` | 480 (08:00) | Minuten seit Mitternacht; kleiner als Beginn = über Mitternacht |
| `notificationsWeekendQuiet` | aus | Samstag/Sonntag ganztägig still (unabhängig von den Ruhezeiten) |

Bestehende Schalter, die das Gate ebenfalls auswertet: `breakReminderEnabled`, `idleDetectionEnabled`
(Leerlauf-Mitteilung folgt daraus), `budgetWarningsEnabled`.

## Gate (`NotificationGate.allows(kind:now:settings:calendar:)`)

Reihenfolge:
1. Schalter der Art aus → unterdrückt (`.disabled`).
2. Art `forgottenTimer` oder `test` → erlaubt (ignoriert Ruhezeiten und Wochenende).
3. „Am Wochenende still“ und `calendar.isDateInWeekend(now)` → unterdrückt (`.weekend`).
4. Ruhezeiten an und Minute in `start..<end` (über Mitternacht, wenn `end < start`; `start == end`
   = leer) → unterdrückt (`.quietHours`).

Unterdrücktes wird geloggt (Subsystem `dev.eremiya.takt`, Kategorie `focus`), z. B.
„Mitteilung „Pomodoro“ unterdrückt: Ruhezeit 18:00–08:00.“ `verdict(…)` liefert den Grund ohne Log.

Geplante Mitteilungen prüfen zum Auslösezeitpunkt: Pausenerinnerung mit `now = fireDate`, geplanter
Block mit `now = block.startAt`. Ändern sich Schalter oder Ruhezeiten, plant der Reiter über
`BreakReminder.settingsDidChange()` beide neu.

| Art | Stelle | Wirkung bei „aus“ |
|---|---|---|
| `breakReminder` | `BreakReminder.reschedule` | keine Erinnerung, keine Musik-Pause |
| `plannedBlock` | `BreakReminder.reschedulePlanned` | keine Mitteilung; Block in „Heute“ bleibt |
| `pomodoro` | `PomodoroController.deliver` | keine Mitteilung; Phasen und Einblendung laufen |
| `idle` | `IdleDetector.postNotification` | (App inaktiv) keine Nachfrage – Zeit bleibt erfasst |
| `forgottenTimer` | `ForgottenTimerGuard.check`/`postNotification` | weder Alert noch Mitteilung |
| `budget` | `BudgetWatcher.notify` | keine Mitteilung |
| `activity` | `ActivityMonitor.notify` | Vorschläge und Auto-Start ohne Mitteilung |
| `test` | `NotificationPermission.sendTest` | immer erlaubt |

## Reiter „Mitteilungen“

Reihenfolge der Reiter: Allgemein · **Mitteilungen** · Musik · Fokus · Widget · Abrechnung · Kalender ·
Aktivität. Fenster 640 × 460 pt.

- **System:** Status aus `notificationSettings()` – erlaubt (bei Hinweisstil „Keine“: „Erlaubt, aber
  ohne Banner“) / verweigert / nicht entschieden. Knopf „In Systemeinstellungen öffnen“
  (`x-apple.systempreferences:com.apple.Notifications-Settings.extension`) bzw. „Erlauben“. Neu gelesen
  beim Erscheinen und wenn Takt wieder aktiv wird. „Testmitteilung senden“ zeigt Uhrzeit oder Fehler.
- **Mitteilungsarten:** je Zeile Symbol, Titel, dezenter Parameter, Kurzbeschreibung, „Details →“ und
  Schalter: Pausenerinnerung (nach 75 Min → Fokus) · Pomodoro (Arbeit/Pause, „Mit Ton“ → Fokus) ·
  Leerlauf (ab 10 Min → Fokus) · Vergessener Timer (nach 8 h → Allgemein) · Budget (80 % · 100 %) ·
  Aktivität (nach 10 Min → Aktivität) · Geplanter Block (zum Beginn) · Termin-Hinweis „in der App“
  (→ Kalender).
- **Ruhezeiten:** Schalter, zwei `DatePicker` (Stunde/Minute), „Am Wochenende still“; Fußzeile mit
  „Gerade Ruhezeit – Mitteilungen ruhen bis 08:00.“ (minütlich aktualisiert) und „Vergessener Timer
  bleibt aktiv“.

## Navigation

`SettingsView` hält die Auswahl als `@State SettingsTab` (`general, notifications, music, focus, widget,
billing, calendar, activity`). Sie beobachtet `AppNavigator.requestedSettingsTab` (Navigator optional
aus der Umgebung, `onChange(initial: true)`), wechselt den Reiter und ruft `consumeSettingsTab()`.
Unbekannte Kennungen werden verworfen.
