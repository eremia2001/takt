# Verständlichkeit: Einstellungen, Bereiche, Menüleiste

Ziel: Jede Einstellung erklärt sich selbst, jeder leere Bereich sagt, was zu tun ist, und Begriffe
heißen überall gleich. Ergänzt `SPEC.md` und die Teil-Specs; ändert kein Verhalten.

## Bausteine

| Datei | Inhalt |
|---|---|
| `Takt/Support/TipStore.swift` | `TipID` (Heute, Berichte, Projekte, Menüleiste) mit Text; `TipStore.shared` merkt ausgeblendete Tipps in `UserDefaults` (`tips.dismissed`, Liste der Kennungen; `resetAll()`); `TermHelp` – Tooltips der wiederkehrenden Begriffe; `HelpLink` „Mehr in der Hilfe →“; `HelpOpener` |
| `Takt/Support/HintViews.swift` | `TipRow` (Glühbirne, Text, optional Link, ×), `PermissionRow` + `PermissionState`, `SettingsIntro`, `SettingHint`, `EmptyStateView` |

Beide ohne Store- und TaktCore-Abhängigkeit; `HelpLink` liest nur den optionalen `AppNavigator`.

### Hilfe-Links

`HelpLink(topic:)` ruft `AppNavigator.request(helpTopic:)` (Navigator optional in der Umgebung).
Ohne Navigator geht die Anfrage über die Responder-Kette: `NSApp.sendAction("showHelpWindow:")` mit
einem `HelpTopicSender` (`@objc topic`); antwortet niemand, passiert nichts. Kennungen wie im
Hilfe-Fenster: `start`, `menubar`, `notifications`, `music`, `focus`, `widget`, `billing`, `calendar`,
`activity`, `reports` (Aliasse wie `general`, `today`, `projects` löst das Hilfe-Fenster auf).

### Tipps

Einmalig, bis zum Klick auf ×; dezent (Glühbirne, `track`-Fläche, 12 pt):

| Tipp | Ort | Text |
|---|---|---|
| `today` | Heute, unter der Schnelleingabe | „⌘K öffnet die Befehlspalette · ⌘N springt in die Schnelleingabe“ |
| `reports` | Berichte, über der Projekt-Tabelle | „Projektzeile anklicken zeigt Einträge und Tags des Zeitraums“ |
| `projects` | Projekte, über der Liste (ab 2 Projekten) | „Rechtsklick für Bearbeiten/Archivieren · Ziehen sortiert · Doppelklick öffnet“ |
| `menuBar` | Menüleisten-Fenster, über der Fußzeile, mit „Öffnen“ | „Stil der Menüleiste: Einstellungen › Allgemein“ |

### Freigaben (`PermissionRow`)

Eine Zeile: graues Symbol, Name, Status (grün erlaubt · orange nicht entschieden/eingeschränkt · rot
abgelehnt), Knopf („Erlauben“ bei nicht entschieden, sonst „Systemeinstellungen…“), darunter ein Satz,
wofür. Eingesetzt in:

- **Mitteilungen** (Reiter Mitteilungen, Fokus, Aktivität bei eingeschalteter Erkennung):
  `NotificationPermissionRow` liest den Status selbst (Erscheinen, App wieder aktiv).
- **Automation Spotify/Musik** (Reiter Musik, je nach Anbieter): `AutomationPermission.state` über
  `AEDeterminePermissionToAutomateTarget` abseits des Main-Threads; „Erlauben“ zeigt die Systemabfrage.
  Läuft die App nicht, meldet macOS keinen Status → „Prüfbar, wenn die App läuft“.
- **Bedienungshilfen** (Musik bei „Medientaste senden“, Aktivität).
- **Kalender** (Reiter Kalender).

## Einstellungen

- Jeder Reiter beginnt mit `SettingsIntro` (Symbol + „Hier stellst du ein, …“) und endet mit
  „Mehr in der Hilfe →“ (`SettingsPage` in `SettingsView`).
- Jede Einstellung hat einen Satz Erklärung (zweiter `Text` im Label bzw. `.caption` darunter);
  Werte mit Einheit („75 Min“, „8 h“, „h pro Woche“, „EUR/h“), Standard als Hinweis („Standard: 75 Min“).
- Reiter-Symbole: Allgemein `gearshape`, Mitteilungen `bell.badge`, Musik `music.note`,
  Fokus `brain.head.profile`, Widget `rectangle.3.group`, Abrechnung `eurosign.circle`,
  Kalender `calendar`, Aktivität `sparkles`. Fenster bleibt 640 × 460 (acht Reiter passen, siehe Harness).

| Reiter | Reihenfolge / Gruppen |
|---|---|
| Allgemein | Menüleiste (anzeigen, Stil + Vorschau, Projektname, Tagessumme, Wenn nichts läuft, Schnelleingabe im Fenster, Dock-Symbol) · Kurzbefehle überall (Timer starten/stoppen, Schnelleingabe öffnen – je mit „Standard: ⌃⌥⌘T/N“) · Vergessener Timer |
| Mitteilungen | Freigabe + Testmitteilung · Mitteilungsarten (Tooltips auf Parameter und Schalter) · Ruhezeiten |
| Musik | Musik (Schalter, Anbieter, Standard-Quelle, Stoppen, Übernehmen, Medientaste) · Freigaben |
| Fokus | Freigabe Mitteilungen · Pausen · Leerlauf · Pomodoro |
| Widget | Aussehen · Widget hinzufügen (drei Schritte) |
| Abrechnung | Satz und Ziel (Standard-Stundensatz, Wochenziel) · Berechnung (Rundung mit Beispiel, Währung) |
| Kalender | Zugriff (`PermissionRow`, Termine in „Heute“) · ohne Zugriff: was damit möglich wäre · mit Zugriff: Angezeigte Kalender, Spiegeln (Konto, Mindestdauer „Standard: 5 Min“), Regeln mit Beispielzeile |
| Aktivität | Aktivität (Schalter, Bedienungshilfen, ggf. Mitteilungen, Nachfragen, Automatisch starten) · Regeln mit Beispielzeile · Zuletzt erkannt |

## Leere Zustände

- **Heute ohne Projekte und Einträge:** Karte „Noch keine Projekte“ mit drei Schritten, Knopf
  „Projekt anlegen“ (öffnet den Projekt-Editor direkt, `TodayActions.createProject`) und Hilfe-Link
  (`start`). Nur archivierte Projekte: „Kein aktives Projekt zum Starten.“ + „Projekt anlegen“.
- **Heute ohne Einträge:** „Starte einen Timer über eine Kapsel oben oder tippe ⌘N: „Kundenportal 9-10:30“.“
- **Projekte:** `EmptyStateView` mit „Projekt anlegen“; nur Archiv: Hinweis über der Liste.
- **Berichte:** Zeitraum/Jahr ohne Einträge → `EmptyStateView` (blättern, wie Einträge entstehen,
  Toggl-Import); freier Tag wie bisher.
- **Regeln** (Kalender, Aktivität): ausgegraute Beispielzeile + Satz, wie man eine anlegt.
- **Kalender ohne Zugriff:** Liste, was mit Zugriff geht.

## Begriffe und Tooltips

`TermHelp` hält die Tooltips für „Nächster Schritt“, „Block planen“ (Wenn-dann-Plan), „Wechsel“,
„Längster Block“ (Lücken bis 5 Min), „Abrechenbar“, „Gerundet“, „Eff. Satz“, „Satz“, „Wochenziel“,
„Weiter mit“. „Eff. Satz“ steht zusätzlich als Legende unter der Projekt-Tabelle ausgeschrieben.
Tooltips mit Kürzel, wo es eins gibt („Stoppen (⌘.)“, „Einstellungen öffnen (⌘,)“).

## Menüleisten-Fenster

- Kopf der Projektliste „Projekte · Klick startet“ (ohne Knopf „Schnelleingabe…“, sonst nur „Projekte“)
  und Link „Stil ändern…“: fordert `SettingsTab.general` über den optionalen `AppNavigator` an und
  öffnet dann die Einstellungen.
- Tipp `menuBar` mit „Öffnen“; Tooltips auf Karte, Pomodoro-Zeile, Projekten und Fußzeile.

## Prüfen

- Build: `xcodegen generate && xcodebuild -project Takt.xcodeproj -scheme Takt -configuration Debug
  -derivedDataPath .build/dd-uxsettings -allowProvisioningUpdates build`.
- Render-Harness (Scratchpad `uxsettings/build.sh`): alle App-Quellen ohne `@main` + In-Memory-Store als
  kleines `.app`-Bundle (Mitteilungen brauchen ein Bundle), PNGs hell/dunkel.
- Tipps zurücksetzen: `defaults delete dev.eremiya.takt tips.dismissed`.
