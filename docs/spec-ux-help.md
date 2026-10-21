# Hilfe, Einführung und App-Menü

Ziel: Funktionen auffindbar und verständlich machen – wo man was einstellt, welche Kürzel es gibt.
Alles offline, Texte in einfachem Deutsch.

## Dateien

| Datei | Inhalt |
|---|---|
| `Takt/Help/HelpContent.swift` | Strukturierte Inhalte: `HelpTopic`, `HelpBlock` (Überschrift, Absatz mit Inline-Markdown, Liste, „So geht’s“-Schritte, Kürzel-Tabelle, Beispiele, Tipp, Hinweis, Link, lebender Baustein), `HelpDestination`, `HelpContext` (Platzhalter `{toggle}`/`{quick}`), Suche, Aliasse. Ohne Store/TaktCore |
| `Takt/Help/HelpWindow.swift` | Hilfe-Fenster (rein darstellend): Suchfeld (⌘F), Themenliste, Inhalt mit „Dort hin“; `HelpKeyCap`, `HelpStepsCard`, `HelpShortcutTable`, `HelpExampleTable`, `HelpMarkdown` |
| `Takt/Help/HelpScene.swift` | Szene `Window(id: "help")`: verbindet mit Navigator, Einstellungen, Menüleiste, Freigaben; `HelpContext.current(settings)` |
| `Takt/Help/HelpCenter.swift` | `HelpCenter.shared.show(topicID:)` – öffnet das Fenster von überall (registrierte `OpenWindowAction`, sonst `takt://help/<thema>`); `registerHelpWindowOpener()`; `SpecDocument.url` |
| `Takt/Help/AppRouter.swift` | Führt `HelpDestination` aus (Bereich, Einstellungs-Reiter, Palette, Schnelleingabe-Fenster, Einführung, Aktion, Datenbank im Finder) und holt das Hauptfenster nach vorn |
| `Takt/Help/AppMenuCommands.swift` | App-Menü (`Commands`) |
| `Takt/Help/PermissionList.swift` | `PermissionKind`, `PermissionList` (nutzt `PermissionRow` aus `Support/HintViews.swift`) |
| `Takt/Help/PermissionCenter.swift` | Status/Abfrage aller vier Freigaben über die vorhandenen Stellen |
| `Takt/Help/HelpDataLocation.swift` | Datenbankpfad, „Im Finder zeigen“, Sicherungen `takt.sqlite.bak-*` |
| `Takt/Help/de.lproj/Help.strings` | Leer; sorgt dafür, dass das Bundle „de“ führt → Standardmenüs auf Deutsch |
| `Takt/Onboarding/OnboardingView.swift` | Einführung, 5 Seiten (rein darstellend), `TaktGlyph`, `WidgetGalleryIllustration` |
| `Takt/Onboarding/OnboardingSheet.swift` | Anbindung: Projekt anlegen, Freigaben, Flags |
| `Takt/Onboarding/OnboardingInfo.swift` | Wann Einführung bzw. Hinweis „Neu“ erscheinen (`currentVersion = 1`) |
| `Takt/Onboarding/WhatsNewBanner.swift` | Hinweis „Neu: Befehlspalette ⌘K · Schnelleingabe ⌘N · Hilfe ⌘?“ |

Geändert: `TaktApp` (Menü, Hilfe-Fenster, `AppDelegate.showHelpWindow:`), `MainView`, `WindowHeader`,
`AppNavigator`, `AppSettings` (`onboardingCompleted`, `onboardingVersion`), `CommandRegistry`.

## Fensterkopf

Tabs · **⌘K Befehle** (dezente Kapsel, öffnet die Palette) · **?** (Hilfe) · Zahnrad. Tooltips mit
Kürzel: „Heute (⌘1)“, „Befehlspalette (⌘K) …“, „Hilfe (⌘?)“, „Einstellungen (⌘,)“.

Unter dem Kopf einmalig der Hinweis „Neu: …“ mit „Ausprobieren“ (öffnet die Palette), „Hilfe öffnen“
und ×. Er gilt als gesehen, sobald er erscheint (`onboardingVersion = 1`).

## App-Menü

| Menü | Einträge |
|---|---|
| Takt | … Einstellungen … (⌘,), **Freigaben …** |
| Ablage | Neuer Eintrag …, Neues Projekt … · Einträge als CSV exportieren …, Zusammenfassung als CSV exportieren …, Timesheet als PDF … · Toggl importieren … |
| Bearbeiten | Standard |
| Darstellung | Heute ⌘1, Berichte ⌘2, Projekte ⌘3 · Bericht: Tag ⌥⌘1, Woche ⌥⌘2, Monat ⌥⌘3, Jahr ⌥⌘4 · Standard (Vollbild …) |
| Timer | Starten › (aktive Projekte, laufendes markiert) · Stoppen ⌘. · Weiter mit ‹Projekt› ⌃⌥⌘T · Schnelleingabe ⌘N · Schnelleingabe-Fenster ⌃⌥⌘N · Block planen … · Befehle … ⌘K |
| Fenster | Standard (+ Takt-Hilfe) |
| Hilfe | Takt-Hilfe ⌘? · Tastaturkürzel … · Freigaben prüfen … · Einführung erneut zeigen … · Spezifikation öffnen (nur wenn `docs/SPEC.md` existiert) |

- **Kürzel-Konflikte:** AppKit fragt bei Tastenäquivalenten zuerst das Schlüsselfenster, dann das
  Menü. ⌘1–3 (Tabs), ⌘N (Feld in „Heute“), ⌘. (Stopp-Popover) und ⌘K (unsichtbarer Knopf in `MainView`)
  bleiben deshalb in den Ansichten; das Menü greift nur, wo sie nicht sichtbar sind, und tut dasselbe
  über Navigator bzw. Menüleiste (⌘N → schwebendes Schnelleingabe-Fenster, ⌘. → Stopp ohne Notiz mit
  Einblendung). Solange die Palette offen ist (`AppNavigator.isPaletteShown`), sind ⌘1–3, ⌥⌘1–4, ⌘N
  und ⌘. im Menü aus – ⌘1–9 gehören der Palette.
- **⌥⌘ statt ⇧⌘ für Berichte:** Auf deutscher Tastatur liefert ⇧1 das Zeichen „!“; das Menü erkennt
  ⇧⌘1 dann nicht (im Prozess mit synthetischen Ereignissen geprüft). ⌥⌘1 funktioniert.
- **Globale Kurzbefehle** (Start/Stopp, Schnelleingabe-Fenster) stehen mit der eingestellten
  Kombination im Menü. Das System fängt sie vorher ab (Carbon-Hotkey), das Menü zeigt sie nur an.
  Lässt sich die Taste nicht als Menü-Kürzel darstellen (z. B. F5), steht sie im Titel.
- **Deutsche Menüs:** Ohne Lokalisierung „de“ im Bundle zeigt macOS „File/Edit/View“. Die leere
  `Help/de.lproj/Help.strings` reicht, damit Ablage/Bearbeiten/Darstellung/Fenster/Hilfe deutsch sind.

## Aktionen (`AppNavigator.requestedAction`)

`AppAction`: `exportEntriesCSV, exportSummaryCSV, exportTimesheetPDF, importToggl, planBlock, newProject,
newEntry`. `MainView` wechselt in den zuständigen Bereich (Export/Import → Berichte, Eintrag/Block →
Heute, Projekt → Projekte) und wartet 200 ms. Hat die Ansicht die Anforderung bis dahin nicht mit
`consumeAction()` übernommen, führt `MainView` sie selbst aus:

| Aktion | Fallback in `MainView` |
|---|---|
| Einträge/Zusammenfassung als CSV | `CommandRegistry.export` (laufender Monat, Sichern-Dialog) |
| Timesheet als PDF | `TimesheetExportSheet` mit dem laufenden Monat |
| Toggl importieren | `TogglImportSheet` |
| Neues Projekt | `ProjectEditor` (neu) |
| Neuer Eintrag | `EntryEditor` (letzte Stunde, zuletzt genutztes Projekt); ohne Projekte Hinweis |
| Block planen | Hinweis „in ‚Heute‘ unter der Karte auf ‚Block planen …‘ klicken“ – das Popover ist privat in `TodayScreen` |

Später können `ReportsView`, `TodayView`, `ProjectsView` die Aktion selbst übernehmen
(`onChange(of: navigator.revision)` → `consumeAction()`), z. B. Export mit dem gezeigten Zeitraum.

## Hilfe

Themen (Kennung): Erste Schritte (`start`), Tastaturkürzel (`shortcuts`), Befehlspalette ⌘K
(`palette`), Schnelleingabe (`quickentry`), Widget (`widget`), Menüleiste (`menubar`), Musik
(`music`), Fokus (`focus`), Projekte & Abrechnung (`billing`), Berichte & Export (`reports`), Kalender
(`calendar`), Aktivität (`activity`), Mitteilungen & Ruhezeiten (`notifications`), Freigaben
(`permissions`), Daten & Sicherung (`data`). Aliasse: `general→menubar`, `today→start`,
`projects→billing`, `timer→focus`, `export→reports`, `pomodoro→focus`, `privacy→permissions` u. a.;
unbekannt → Erste Schritte.

Öffnen: ⌘?, „?“ im Fensterkopf, Hilfe-Menü, Palette („Takt-Hilfe“, „Hilfe: ‹Thema›“ bei Suche),
`AppNavigator.request(helpTopic:)`, `NSApp.sendAction("showHelpWindow:")` mit Absender, der `topic`
per KVC liefert (Links „Mehr in der Hilfe →“ aus `Support/TipStore.swift`), `takt://help/<thema>`.

Suche: alle Wörter müssen im Thema vorkommen (Titel, Suchbegriffe, sämtliche Texte; ohne
Groß-/Kleinschreibung und Akzente); Treffer im Titel zuerst. ↩ im Suchfeld wählt den ersten Treffer.

## Freigaben (`PermissionCenter`)

| Freigabe | Status | Erlauben | Systemeinstellungen |
|---|---|---|---|
| Mitteilungen | `NotificationPermission.status` | `NotificationPermission.request` | `NotificationPermission.openSystemSettings` |
| Automation | `AEDeterminePermissionToAutomateTarget` (Spotify, Musik; nur installierte; ohne laufende App „Unbekannt“) | startet die App unsichtbar und fragt (abseits des Main-Threads) | `Privacy_Automation` |
| Kalender | `EKEventStore.authorizationStatus` | `CalendarService.requestAccess` (sonst EventKit direkt) | `Privacy_Calendars` |
| Bedienungshilfen | `ActivityProbe.isTrusted` | `ActivityProbe.requestTrust` | `Privacy_Accessibility` |

Neu gelesen beim Erscheinen und bei jeder Aktivierung von Takt.

## Einführung

Fünf Seiten, 620 × 520 pt, Weiter (↩, außer im Namensfeld)/Zurück/Überspringen, Punkte unten mittig:
1. Willkommen (Takt-Zeichen, vier Merkmale) · 2. Erstes Projekt (Name, Farbe aus `ProjectPalette`,
Business/Privat → `store.saveProject`; ↩ im Namensfeld legt an) · 3. Widget (Illustration aus Formen,
vier Schritte, Mitteilungszentrale als Alternative, Link zur Hilfe) · 4. Freigaben (`PermissionList`) ·
5. Kürzel (⌘K, ⌘N, ⌃⌥⌘T, ⌃⌥⌘N mit eingestellten Kombinationen) + Fertig.

- Erscheint, wenn es keine Projekte gibt (höchstens einmal je App-Start; nie bei Datenbankfehler).
- Fertig und Überspringen setzen `onboardingCompleted = true`, `onboardingVersion = 1`.
- Bestehende Nutzer mit Projekten: `onboardingCompleted` wird still gesetzt, stattdessen der Hinweis „Neu“.
- Erneut: Hilfe › Einführung erneut zeigen …, Palette „Einführung zeigen“, `takt://onboarding`.
- Es gibt keine öffentliche Schnittstelle, die Mitteilungszentrale oder die Widget-Galerie zu öffnen –
  Seite 3 erklärt den Weg deshalb in Schritten.

## Prüfen

- Build: `xcodegen generate && xcodebuild -project Takt.xcodeproj -scheme Takt -configuration Debug
  -derivedDataPath .build/dd-uxhelp -allowProvisioningUpdates build`.
- Render-Harness (ohne Store): Fensterkopf mit Hinweis, Hilfe-Themen, Einführung Seiten 1–5, hell/dunkel.
