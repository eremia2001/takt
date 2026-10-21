# Befehlspalette (⌘K)

Alles per Tastatur: ⌘K im Hauptfenster legt eine Spotlight-artige Palette über das Fenster.

## Bedienung

- **Öffnen:** ⌘K im Hauptfenster (erneut ⌘K schließt). Aus der Menüleiste: Zeile **„Befehle… ⌘K“**
  über der Fußzeile des Popovers. Sie holt das Hauptfenster nach vorn (öffnet es, falls geschlossen)
  und öffnet dort die Palette.
- **Aussehen:** 600 pt breit, oben zentriert unter dem Fensterkopf, abgedunkelter Hintergrund
  (Klick daneben schließt). Material und Rahmen wie das Schnelleingabe-Fenster (`DesignTheme`).
- **Tasten:** Tippen filtert. ↑/↓ wählen (am Ende geht es oben weiter), ↩ führt aus, ⌘1–⌘9 führen
  direkt den 1.–9. Treffer aus (rechts an der Zeile angezeigt). Esc stufenweise: Rückfrage
  abbrechen → Suchtext leeren → Palette schließen.
- **Liste:** höchstens acht Zeilen sichtbar, der Rest scrollt (die angeschnittene nächste Zeile
  zeigt, dass mehr kommt). Treffer sind in Gruppen sortiert.
- Solange die Palette offen ist, sind die Kurzbefehle des Fensters darunter (⌘1–3, ⌘N …)
  ausgeschaltet; ⌘1–9 gehören dann der Palette.

## Suche

Unscharf, ohne Groß-/Kleinschreibung und Akzente. Jedes Wort der Eingabe muss passen:

1. Wortanfang im Titel („kun“ → „Starten: **Kun**denportal“), das erste Wort zählt am meisten,
2. Anfangsbuchstaben („bw“ → „**B**ericht: **W**oche“),
3. Suchbegriffe des Befehls („csv“, „pomodoro“, „spotify“ …),
4. Teilwort im Titel, Wortanfang im Untertitel,
5. dichte Buchstabenfolge ab drei Zeichen (höchstens wenige Lücken).

Gruppen werden nach ihrem besten Treffer sortiert. Zuletzt genutzte Befehle bekommen einen Zuschlag.

**Ohne Suchtext:** zuerst „Zuletzt“ (höchstens 5, `UserDefaults` `commandPalette.recentCommands`),
dann alle Gruppen in fester Reihenfolge. „Archivieren“ und die Einstellungs-Reiter erscheinen erst
beim Suchen.

## Befehle

| Gruppe | Befehl | Wirkung |
|---|---|---|
| Timer | Stoppen *(nur wenn ein Timer läuft; Untertitel Projekt · Dauer)* | `store.stop(nextStep: nil)`, Hinweis „… gestoppt · h:mm“ |
| Timer | Weiter mit ‹letztes Projekt› *(nur wenn nichts läuft; Untertitel nächster Schritt)* | `store.start(projectId:)` |
| Projekte | Starten: ‹Projekt› *(alle aktiven außer dem laufenden; Farbpunkt, Kapsel Business/Privat, Kunde als Untertitel)* | `store.start(projectId:)` |
| Projekte | Neues Projekt … | Bereich Projekte + Hinweis „oben rechts auf „+ Projekt“ klicken“ |
| Projekte | Archivieren: ‹Projekt› *(erst bei Suche)* | Rückfrage in der Palette (↩ bestätigt, Esc bricht ab), dann `store.archive` |
| Navigation | Heute · Berichte · Projekte | `navigator.request(section:)` |
| Navigation | Einstellungen | Einstellungen-Fenster öffnen |
| Berichte | Bericht: Tag · Woche · Monat · Jahr | `navigator.request(reportKind:)` (wechselt auch zu „Berichte“) |
| Export | Einträge als CSV … · Zusammenfassung als CSV … *(Untertitel aktueller Monat)* | Bericht des laufenden Monats → `CSVExport` → `CSVExporter.save` (Sichern-Dialog), Hinweis „Gespeichert: …“ |
| Einstellungen | Einstellungen: Allgemein · Musik · Fokus · Widget · Abrechnung · Kalender · Aktivität · Mitteilungen *(erst bei Suche)* | `navigator.request(settingsTab:)` mit `general, music, focus, widget, billing, calendar, activity, notifications`, dann Fenster öffnen |
| Schnelleingabe | Schnelleingabe-Fenster öffnen *(Untertitel Kurzbefehl)* | schwebendes Schnelleingabe-Fenster |
| Schnelleingabe | Eintragen: ‹Projekt› / Starten: ‹Projekt› *(dynamisch)* | übernimmt die Eingabe wie das Schnelleingabe-Feld |

### Schnelleingabe-Treffer

Sieht der Suchtext wie eine Schnelleingabe aus – er enthält Ziffern oder `#`, oder kein Befehl passt –
und liefert die Vorschau (`QuickEntryEngine.preview`) einen gültigen Eintrag oder Start, steht
**ganz oben** „Eintragen: ‹Projekt›“ (Untertitel: Tag, Spanne, Dauer, #Tag, Notiz) bzw.
„Starten: ‹Projekt›“ (ab Uhrzeit, #Tag, Notiz). ↩ übernimmt (`QuickEntryEngine.commit`), die
Bestätigung erscheint als kurzer Hinweis unten im Fenster, Fehler im Fehler-Alert.

- Ein bloßer Start ohne Zusatz („Website“) erzeugt keinen Treffer – den deckt „Starten: Website“ ab.
- Passt das Projekt mehrdeutig („kun 2h“), gibt es je Kandidat einen Treffer (höchstens drei),
  aufgelöst wie die Kapseln der Schnelleingabe (`QuickEntryEngine.resolve`).
- Schnelleingabe-Treffer landen nicht in „Zuletzt“.

## Technik

- `Takt/CommandPalette/Command.swift` – `Command` (`id, title, subtitle, group, keywords, icon,
  colorHex, badge, showsWhenEmpty, priority, isTransient, confirmation, perform`), `PaletteGroup`
  (nicht `CommandGroup` – der Name gehört SwiftUI), `CommandMatcher` (Suche), `CommandRanking`
  (Abschnitte), `CommandRecents`, `CommandPaletteRequest` (Öffnen aus der Menüleiste: Merker +
  Notification, `MainView` liest beides). Ohne Store/TaktCore – läuft im Render-Harness.
- `Takt/CommandPalette/CommandPaletteView.swift` – `CommandPaletteOverlay` (Abdunkelung) und
  `CommandPaletteView` (rein darstellend, `@FocusState`). ↑ ↓ Esc ⌘1–9 über unsichtbare Knöpfe mit
  `keyboardShortcut` (Tastenäquivalente greifen vor dem Textfeld); die Aktionen lesen Treffer und
  Auswahl erst beim Auslösen. ↩ über `onSubmit`.
- `Takt/CommandPalette/CommandRegistry.swift` – baut die Befehle aus Store, Einstellungen,
  `AppNavigator`; Schnelleingabe-Treffer; CSV-Export des Monats. `CommandPaletteQuickEntry` hält ein
  eigenes `QuickEntryPanelController` (MainView kennt den `MenuBarController` nicht).
- `MainView` – `.overlay` mit der Palette, unsichtbarer Knopf ⌘K, Inhalt `.disabled` solange offen,
  kurzer Hinweis unten, übernimmt `navigator.requestedSection` (`consumeSection`) bei jeder
  Anforderung und beim Erscheinen. Befehle laufen erst nach dem Schließen (Dialoge sollen nicht hinter
  dem Overlay aufgehen).
- `MenuBarPanel`/`MenuBarContent` – optionale Aktion `openCommandPalette` und Zeile „Befehle… ⌘K“.

## Nicht umgesetzt

- **„Block planen…“** fehlt: Der Dialog (`TodayPlanBlockPopover`) ist privat in `TodayScreen` und wird
  über einen internen `@State` geöffnet; `TodayActions.planBlock` speichert nur einen fertigen Block.
  Für den Befehl bräuchte „Heute“ eine Anforderung zum Öffnen des Popovers (z. B. über `AppNavigator`).
- Kein Eintrag im App-Menü (`.commands`), weil `TaktApp` nicht geändert werden sollte; ⌘K gilt im
  Hauptfenster.
