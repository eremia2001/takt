# Menüleisten-Stile & Schnelleingabe überall

Ergänzt `SPEC.md` (Menüleiste & Kurzbefehl, Erfassung v3, Fokus v2).

## Menüleisten-Stile (`Takt/MenuBar/MenuBarLabelRenderer.swift`)

Das Label wird als **ein** `NSImage` per `ImageRenderer` gezeichnet (Scale 2, Höhe 22 pt, Breite nach
Inhalt), weil die Menüleiste SwiftUI-Formen nur einfarbig zeigt. Neu erzeugt bei jeder Änderung der
gelesenen Werte: Minutentakt (`MenuBarController.now`), Pomodoro-Restminute (`pomodoro.tick`), Store,
Einstellungen, Helligkeit der Menüleiste.

- **Template oder farbig:** Ohne laufenden Timer ist alles einfarbig → `isTemplate = true`, macOS färbt
  passend (auch hervorgehoben). Läuft ein Timer → `isTemplate = false`; Text/Glyphe weiß bzw. Schwarz
  85 % nach `MenuBarAppearance.isDark()` (Fenster der Statusleiste, sonst `NSApp.effectiveAppearance`;
  beobachtet per KVO und `AppleInterfaceThemeChangedNotification` → `MenuBarController.menuBarIsDark`).
- Stile (`menuBarStyle`, Standard `text`):

| Stil | Läuft | Pomodoro-Pause ohne Timer |
|---|---|---|
| `icon` Symbol | Ring-Glyphe (270°-Bogen + Punkt, wie App-Symbol), Punkt in Projektfarbe und größer | Glyphe + „Pause 07:00“ |
| `compact` Kompakt | Farbpunkt + `h:mm` | Tasse + „Pause 07:00“ |
| `text` Text | Farbpunkt + „Projekt · h:mm“ (Name ≤ 22 Zeichen, abschaltbar) | Tasse + „Pause 07:00“ |
| `capsule` Kapsel | Pille 18 pt in `DesignColor.behindWhite` (helle Farben abgedunkelt), weißer Text „Kundenportal · 1:24“ bzw. „1:24“ | graue Pille mit Tasse + „Pause 07:00“ |
| `ring` Ring | 16-pt-Ring + `h:mm`; Füllung: Pomodoro-Phase (Pause grau) > Budgetverbrauch (ab 80 % orange, > 100 % rot) > laufende Stunde | grauer Ring (Pausenfortschritt) + „Pause 07:00“ |

- Überall: Pomodoro-Zusatz „· 🍅 23:00“ / „· Pause 07:00“ wie bisher; Budget > 100 % → kleiner roter
  Punkt hinter dem Label.
- `menuBarShowProjectName` (an): Name in Text und Kapsel. `menuBarShowTodayTotal` (aus): Tagessumme statt
  Laufzeit.
- `menuBarIdleMode` (Standard `symbol`): `symbol` = nur Glyphe; `symbolAndTotal` = Glyphe + Summe
  („Heute 4:10“ in Text, graue Pille „Heute 4:10“ in Kapsel, sonst „4:10“); `hidden` = Objekt nur bei
  laufendem Timer oder Pomodoro-Phase eingefügt (`MenuBarLabel.isVisible`, verdrahtet über
  `MenuBarExtra(isInserted:)` in `TaktApp`).
- Einstellungen › Allgemein › „Menüleiste“: Picker Stil, Live-Vorschau (`MenuBarStylePreview`, dasselbe
  Bild, „Läuft“ und „Pause“ nebeneinander, Streifen hell/dunkel wie die Einstellungen), „Projektname
  zeigen“ (nur Text/Kapsel), „Tagessumme statt Laufzeit“, Picker „Wenn nichts läuft“.

## Schnelleingabe überall (`Takt/QuickEntry/`)

- `QuickEntryEngine` (Store): Vorschau, Übernehmen (`store.quickEntry` → `store.commit`), Mehrdeutigkeit
  auflösen – gleiche Regeln wie `TodayView`. Liefert `QuickEntryHandlers` für die store-freien Ansichten.
- `QuickEntryField` (`.compact` / `.large`): gleiche Grammatik und Vorschauzeile wie `TodayQuickEntry`
  (dessen View ist an `TodayActions` und ⌘N gebunden, daher eigene). Enter übernimmt, Fehler orange,
  `ambiguousProject` als Kapseln (kompakt bis 3, groß bis 5). Esc: erst leeren, dann abbrechen.
- **Popover:** Feld über der Projektliste (`quickEntryInMenuBar`, nur mit Projekten); nach Erfolg 2,5 s
  „Eingetragen: …“/„Gestartet: …“. Rechts im Feld Knopf „Schnelleingabe…“ (öffnet das schwebende
  Fenster, schließt das Popover). Ohne Feld steht „Schnelleingabe…“ rechts in der Kopfzeile „Projekte“.
- **Schwebendes Fenster** (`QuickEntryPanelController`): randloses `NSPanel` mit `.nonactivatingPanel`,
  `becomesKeyOnlyIfNeeded = false`, `canBecomeKey = true`, `level = .floating`, `hidesOnDeactivate`,
  alle Spaces. 560 × 97 pt, waagrecht mittig, oberes Drittel des Bildschirms mit dem Mauszeiger.
  Großes Feld (22 pt), darunter Vorschau/Fehler/Kapseln bzw. Beispiele + „esc schließen“. Enter →
  übernehmen, schließen, Einblendung `HotKeyOverlay` (neue Art `.saved` mit Häkchen bzw. ▶︎ beim Start).
  Esc (leer) oder Fokusverlust schließt; der Kurzbefehl bei offenem Fenster schließt ebenfalls.
- **Kurzbefehl** Standard ⌃⌥⌘N (`quickEntryHotKey…`), zweite `GlobalHotKey`-Instanz (`id: 2`; der
  gemeinsame Carbon-Handler reicht fremde IDs weiter). Gleiche Kombination wie Start/Stopp → Hinweis
  statt Anmeldung. Während eines der beiden Aufnahmefelder Tasten liest, sind beide abgemeldet.
- Einstellungen › Allgemein › „Schnelleingabe“: „Im Menüleisten-Fenster“, „Schwebendes Fenster per
  Kurzbefehl“, Aufnahmefeld mit „Zurücksetzen“, Hinweis bei Belegung.

## Neue Einstellungen (`AppSettings`)

| Schlüssel | Standard | Werte |
|---|---|---|
| `menuBarStyle` | `text` | `icon`, `compact`, `text`, `capsule`, `ring` |
| `menuBarShowProjectName` | an | |
| `menuBarShowTodayTotal` | aus | |
| `menuBarIdleMode` | `symbol` | `symbol`, `symbolAndTotal`, `hidden` |
