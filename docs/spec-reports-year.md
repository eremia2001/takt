# Berichte – Reiter „Jahr“

Oberfläche zum Jahresbericht aus v5 (`AppDatabase.yearReport`, `TaktStore.yearReport`). Keine Änderung
an TaktCore, Store oder Einstellungen.

## Auswahl

- Segment „Tag · Woche · Monat · Jahr · Zeitraum“. `ReportPeriod` kennt kein Jahr; die Oberfläche führt
  es als eigenes `year: Int?` (`ReportsView` → `ReportsScreen` → `ReportsHeader`). `nil` = `period` gilt.
- Wechsel behält den Bezug: Monat/Woche/Tag → Jahr nimmt das heutige Jahr, wenn der Zeitraum heute
  enthält, sonst das Jahr seines Anfangs. Jahr → Monat/Woche/Tag landet heute (aktuelles Jahr) bzw. am
  1. Januar; Jahr → Zeitraum übernimmt 1.1.–31.12.
- ‹ › blättern Jahre, Titel „2026“ (ohne Tausenderpunkt), „Heute“ springt ins aktuelle Jahr.
- Neu geladen bei Wechsel des Jahres, Rundung, Standardsatz, Währung, jeder Datenänderung
  (`ReportsChangeMonitor`) und – solange ein Timer läuft – minütlich. Geladen werden
  `store.yearReport(year:rounding:defaultHourlyRate:)` und `store.entries(in: Jahr)` (für den
  Monatsverlauf je Projekt).

## Inhalt (`YearReportsContent`)

1. **Kennzahlen:** Gesamt h:mm (Beschriftung „+12 % ggü. 2025“, ohne Vorjahr „kein Vorjahr zum
   Vergleich“) · Abrechenbar (je Eintrag gerundet = Grundlage der Beträge, mit Rundungshinweis) ·
   Umsatz (± Vorjahr; ohne Satz „–“) · Ø pro aktivem Tag mit Zahl der aktiven Tage. Das Delta vergleicht
   mit dem **ganzen** Vorjahr (mehr liefert `YearReport` nicht); Tooltip zeigt den Vorjahreswert.
2. **Monate** (Swift Charts, 12 Balken): Umschalter „Stunden | Umsatz“ rechts über dem Diagramm (nur
   wenn irgendein Projekt einen Satz hat). Stunden gestapelt Business (Akzent) / Privat (`secondary`),
   Umsatz einfarbig. Laufender Monat auf leiser Fläche mit fetter Beschriftung, künftige Monate blass.
   Hover: „Oktober 2026 63:07“ (bei gemischten Monaten mit Aufteilung) bzw. Betrag.
3. **Kunden** (Kunde · Projekte · Stunden · Abrechenbar · Betrag; `nil` = „ohne Kunde“) in der
   Reihenfolge von `byClient` (Betrag, dann Dauer), Summenzeile. „Abrechenbar“ je Kunde wird aus den
   Projektzeilen gerundet nachgerechnet (`ClientRow` führt nur die ungerundete Zeit), gleiche
   Zusammenfassung der Kundennamen wie in TaktCore.
4. **Wohin ging die Zeit:** `tagShares` als waagrechte Balken (relativ zum größten Anteil) mit Dauer und
   Prozent; Tags in Akzentfarbe, „Sonstige“ und „ohne Tag“ grau. Ab 800 pt Inhaltsbreite neben den
   Kunden, sonst darunter (max. 520 pt breit).
5. **Projekte:** dieselbe `ReportsProjectTable` wie sonst (`byProject`); aufgeklappt statt Einträgen
   12 Mini-Balken in Projektfarbe (Monatsinitialen, laufender Monat fett, künftige blass, Tooltip je
   Monat), daneben stärkster Monat, aktive Monate, Ø je aktivem Monat, darunter „nach Tag“.

Leerer Zustand: „Keine Einträge in 2024“.

## Export

Im Reiter „Jahr“ bietet „Exportieren“: **Jahr als CSV …** (`Takt_Jahr_2026.csv`) und **Einträge als
CSV …** (`Takt_Einträge_2026.csv`, alle Einträge des Jahres wie sonst). Jahres-CSV
(`CSVExporter.yearCSV`, Format wie `CSVExport`: `;`, Dezimalkomma, CRLF, BOM):

```
Jahr;2026
Währung;EUR
Rundung;auf 15 Min aufgerundet

Monat;Dauer (h:mm);Dauer (dezimal);Business (h:mm);Privat (h:mm);Abrechenbar (dezimal);Betrag;Aktive Tage
Januar;…   (12 Zeilen)
Summe;…

Kunde;Projekte;Dauer (h:mm);Dauer (dezimal);Abrechenbar (dezimal);Betrag
…
Summe;…
```

„Dauer (dezimal)“ ist hier ungerundet (Monate haben keine gerundete Gesamtzeit), „Abrechenbar“ je
Eintrag gerundet. Die Summe der Monatsbeträge kann um Cent vom Jahresbetrag abweichen (Einträge über
Monatsgrenzen werden je Teil gerundet). Ohne jeden Stundensatz bleibt „Betrag“ leer.

## Dateien

`Takt/Views/Reports/YearReportsData.swift` (Daten, Monatsverlauf je Projekt, Formate),
`YearReportsChart.swift` (Diagramm + Umschalter), `YearReportsContent.swift` (Kennzahlen, Kunden,
Tag-Anteile, Aufbau); angepasst: `ReportsData` (Art `.year`, Aktion `exportYear`), `ReportsHeader`,
`ReportsScreen`, `ReportsView`, `ReportsMetrics` (gemeinsame `ReportsTile`/`ReportsBigNumber`,
Beschriftungen aller Kacheln auf einer Linie), `ReportsProjectTable` (zweiter Initialisierer
`init(year:…)`), `Takt/Export/CSVExporter.swift` (`Kind.year`, `fileName(_:year:)`, `yearCSV`).
