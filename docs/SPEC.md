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
