# Effektiver Stundensatz und Timesheet-PDF

## Effektiver Stundensatz (`TaktCore/EffectiveRate.swift`)

Was eine Stunde **investierter** Zeit einbringt: `Betrag ÷ gesamte Zeit` – nicht abrechenbare Zeit
(Akquise, interne Arbeit, gekappte Stunden) zählt mit. Der nominale Satz rechnet dagegen nur mit den
abgerechneten (je Eintrag gerundeten) Stunden.

| API | Rechnung | `nil`/0 |
|---|---|---|
| `Money.rate(amount:seconds:)` | `amount / (seconds/3600)`, auf Cent | Betrag 0, Zeit ≤ 0 |
| `ProjectReportRow.effectiveRate` | `amount / duration` (ungerundet, inkl. nicht abrechenbar) | ohne Betrag |
| `ClientRow.effectiveRate` | `amount / duration` | ohne Betrag |
| `Report.effectiveRate`, `YearReport.effectiveRate` | Gesamtbetrag ÷ Business-Zeit (Privatzeit ausgenommen) | ohne Betrag/Business-Zeit |
| `Report.nominalRate`, `YearReport.nominalRate` | Beträge ÷ gerundete abrechenbare Zeit der Zeilen **mit** Satz | ohne Betrag |
| `Report.nonBillableShare`, `YearReport.nonBillableShare` | nicht abrechenbare ÷ gesamte Zeit der Business-Projekte (ungerundet), 0…1 | 0 |
| `…isEffectiveRateLow(threshold: 0.15)` | effektiv < nominal × (1 − 0,15); bei Projektzeilen gegen den geltenden Satz | – |

Alles berechnete Eigenschaften (keine neuen gespeicherten Felder, `Hashable` unverändert).

### Oberfläche

- **Kachel „Effektiver Satz“** in Woche, Monat und Jahr (nicht Tag/Zeitraum): große Zahl
  „70,91 €/h“, darunter „nominal 84,64 · 17 % nicht abrechenbar“ (zweizeilig, wenn die Kachel
  schmal ist). Mehr als 15 % unter nominal → Zahl in Orange. Ohne Betrag „–“ mit „kein Umsatz im
  Zeitraum“ bzw. „kein Stundensatz hinterlegt“. Tooltip erklärt beide Sätze.
  Ist die Kennzahlen-Reihe schmaler als 820 pt (Fenster unter ~880 pt), steht der Wert als schmale
  Zeile unter den Kacheln – sonst würden fünf Kacheln die anderen Zahlen abschneiden.
- **Spalte „Eff. Satz“** rechts neben „Betrag“ in der Projekt-Tabelle (alle Zeiträume) und in der
  Kunden-Tabelle (Jahr); 12 pt, sekundär, Tooltip „Betrag ÷ gesamte Zeit inkl. nicht abrechenbar“.
  Projektzeilen in Orange, wenn > 15 % unter dem Projektsatz. Die Summenzeile zeigt den Wert des
  Berichts (Business-Zeit, ohne Privat) mit eigener Erklärung. Kundenzeilen ohne Warnfarbe (oft
  mehrere Sätze).

## Navigation

`ReportsView` beobachtet `AppNavigator.revision` und prüft beim Erscheinen `requestedReportKind`.
Eine Anforderung bezieht sich immer auf heute: Tag/Woche/Monat → `.day/.week/.month(now)`, Jahr → das
aktuelle Jahr. Danach `consumeReportKind()`.

## Timesheet (`TaktCore/Timesheet.swift`)

`Timesheet.make(entries:projects:interval:scope:options:defaultHourlyRate:calendar:)`

- `TimesheetScope`: `.all`, `.client(String)` (Vergleich getrimmt, ohne Groß-/Kleinschreibung und
  Akzente – wie `YearReport.byClient`), `.project(UUID)`.
- `TimesheetOptions`: `billableOnly`, `rounding` (`.none` = exakt).
- Einträge werden auf den Zeitraum zugeschnitten (wie im Bericht), je Eintrag aufwärts gerundet,
  Satz = Projekt, sonst Standard. **Laufende Einträge nie** – sie stehen in `excludedRunning`.
- Zeilen chronologisch, `days` nach Tag des Beginns (Eintrag über Mitternacht bleibt am Starttag).
- `rateGroups`: je Satz gerundete Zeit und `Stunden × Satz` auf Cent (geht auf dem Nachweis genau
  auf; Zeilenbeträge je Eintrag können um Cent abweichen). `amount` = Summe, `nil` ohne Satz;
  `hourlyRate` nur bei genau einem Satz.
- `Timesheet.clients(of:)` – Kundenliste ohne Dubletten; `periodTitle` „Oktober 2026“ bzw. Tagesspanne.

## Timesheet-PDF (`Takt/Export/TimesheetPDF.swift`)

- Je Seite eine SwiftUI-View (A4, 595 × 842 pt), `ImageRenderer.render(rasterizationScale:)` zeichnet
  in einen PDF-`CGContext` – Text bleibt Vektor und durchsuchbar.
- Seitenumbruch über ein Höhenbudget: Zeilenhöhen fest (18 pt, je weitere Textzeile +11 pt, höchstens
  drei Zeilen), vorab mit `ImageRenderer` in gleicher Schrift/Breite gemessen (AppKit misst bei 9 pt
  einige Prozent breiter). Ergibt rund 34 Einträge je Seite. Tagessumme wird nicht von ihrem letzten
  Eintrag getrennt, oben auf jeder Seite steht das Datum erneut, Summenzeile + Zusammenfassung stehen
  zusammen auf der letzten Seite.
- Inhalt: „Tätigkeitsnachweis“ + Zeitraum; links Zeitraum/Kunde/Projekt(e), rechts Aussteller
  (entfällt ohne Angabe); Tabelle Datum · Von–Bis · Projekt (nur bei mehreren) · Tätigkeit (Notiz,
  Tag grau, „nicht abrechenbar“ hellgrau; entfällt, wenn nichts davon gezeigt wird) · Dauer (h:mm,
  ungerundet) · Std. ger. (dezimal, gerundet); optional Tagessummen; Summenzeile; Zusammenfassung
  (erfasste/abgerechnete Zeit, davon abrechenbar, Stundensatz bzw. Zeilen „24,25 h × 95,00 €“,
  Betrag) und Hinweise (Rundung, nicht abrechenbare Einträge, Zeit ohne Satz); Fußzeile „Erstellt mit
  Takt am …“ und „Seite x von y“. Nur Grautöne und dünne Linien.
- Dateiname `Timesheet_<Kunde|Projekt|Alle>_2026-10.pdf` (ganzer Monat), `_2026` (Jahr), sonst
  `_2026-10-01_bis_2026-10-15`.

### Sheet (`Takt/Views/Reports/TimesheetExportSheet.swift`)

„Exportieren → Timesheet als PDF …“ (alle Zeiträume, auch Jahr). Zeitraum vorbelegt mit dem
gezeigten Berichtszeitraum; „Für“: Alle Projekte · Kunden · Projekte (aktive, dazu archivierte mit
Einträgen im Zeitraum); haben alle Business-Einträge des Zeitraums denselben Kunden, ist er
vorausgewählt. Kopfzeile: Aussteller (merkt `timesheet.issuer`), Kunde (folgt der Auswahl, frei
änderbar). Optionen (gemerkt unter `timesheet.*`): Nur abrechenbare Einträge, Notizen, Tags,
Tagessummen, Rundung anwenden (aus Einstellungen; ohne Rundung gesperrt). Vorschau: „25 Einträge ·
59:15 h · 60,00 h abgerechnet“, Betrag, Hinweis auf laufenden Eintrag, Dateiname. „PDF sichern…“ →
`NSSavePanel`, danach Bestätigung in den Berichten.
