import Foundation
import GRDB

// MARK: - CSV-Parser

/// Kleiner RFC-4180-Parser: Felder in Anführungszeichen (mit `""` als Escape), Trennzeichen und
/// Zeilenumbrüche innerhalb von Anführungszeichen, CRLF/LF/CR als Zeilenende, optionales BOM.
public enum CSVParser {
    /// Zerlegt den Text in Zeilen aus Feldern. Komplett leere Zeilen entfallen.
    public static func parse(_ text: String, separator: Character = ",") -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var fieldWasQuoted = false

        // Über Unicode-Skalare statt Characters iterieren: „\r\n“ ist in Swift *ein* Character.
        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
        let sep = separator.unicodeScalars.first!

        func endField() {
            row.append(field)
            field = ""
            fieldWasQuoted = false
        }
        func endRow() {
            endField()
            // Zeilen, die nur aus einem leeren Feld bestehen, sind Leerzeilen.
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if inQuotes {
                if scalar == "\"" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                        field.unicodeScalars.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.unicodeScalars.append(scalar)
                }
            } else if scalar == "\"" && field.isEmpty && !fieldWasQuoted {
                inQuotes = true
                fieldWasQuoted = true
            } else if scalar == sep {
                endField()
            } else if scalar == "\r" || scalar == "\n" {
                endRow()
                if scalar == "\r", index + 1 < scalars.count, scalars[index + 1] == "\n" { index += 1 }
            } else {
                field.unicodeScalars.append(scalar)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty || fieldWasQuoted { endRow() }
        return rows
    }
}

// MARK: - Toggl-Import

/// Ein Eintrag aus dem Toggl-Export.
public struct TogglEntry: Hashable, Sendable {
    /// Toggl-Projektname; Einträge ohne Projekt erhalten `TogglImport.noProjectName`.
    public var projectName: String
    public var client: String?
    public var description: String?
    /// `nil`, wenn die Datei keine Spalte „Billable“ hat.
    public var isBillable: Bool?
    public var start: Date
    public var end: Date
    public var tags: [String]
    /// Zeilennummer in der Datei (1 = Kopfzeile), für Hinweise.
    public var line: Int

    public init(
        projectName: String, client: String?, description: String?, isBillable: Bool?,
        start: Date, end: Date, tags: [String], line: Int
    ) {
        self.projectName = projectName
        self.client = client
        self.description = description
        self.isBillable = isBillable
        self.start = start
        self.end = end
        self.tags = tags
        self.line = line
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Ergebnis des Einlesens – noch nichts gespeichert.
public struct TogglImportPreview: Hashable, Sendable {
    public var entries: [TogglEntry]
    /// Alle Toggl-Projektnamen der Datei in Reihenfolge des ersten Auftretens. Ob ein Projekt
    /// wirklich neu angelegt wird, entscheidet erst das Mapping (siehe `suggestedTogglMapping`).
    public var newProjects: [String]
    /// Übersprungene Zeilen (unlesbares Datum, Ende vor Start, …).
    public var skipped: Int
    /// Hinweise für die Oberfläche, höchstens `TogglImport.maxWarnings` (plus Sammelhinweis).
    public var warnings: [String]

    public init(entries: [TogglEntry], newProjects: [String], skipped: Int, warnings: [String]) {
        self.entries = entries
        self.newProjects = newProjects
        self.skipped = skipped
        self.warnings = warnings
    }
}

public enum TogglImportError: Error, Equatable, Sendable, LocalizedError {
    case empty
    case missingColumns([String])

    public var errorDescription: String? {
        switch self {
        case .empty:
            "Die Datei enthält keine Daten."
        case .missingColumns(let columns):
            "Keine Toggl-Detailexport-Datei – es fehlen die Spalten: \(columns.joined(separator: ", "))."
        }
    }
}

/// Liest den Toggl-Track-„Detailed report“ als CSV (Trennzeichen `,`, Datum `YYYY-MM-DD`,
/// Zeit `HH:MM:SS`). Pflichtspalten: `Start date`, `Start time` und entweder `End date` +
/// `End time` oder `Duration`. Optional: `Project`, `Client`, `Description`, `Billable`, `Tags`.
public enum TogglImport {
    public static let noProjectName = "Ohne Projekt"
    public static let maxWarnings = 20

    /// - Parameter calendar: Zeitzone der Uhrzeiten in der Datei (Toggl exportiert in der
    ///   Zeitzone des Profils, in der Regel der eigenen).
    public static func parse(csv: String, calendar: Calendar = .current) throws -> TogglImportPreview {
        let rows = CSVParser.parse(csv, separator: ",")
        guard let header = rows.first else { throw TogglImportError.empty }

        let normalized = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func column(_ name: String) -> Int? { normalized.firstIndex(of: name) }

        let startDate = column("start date")
        let startTime = column("start time")
        let endDate = column("end date")
        let endTime = column("end time")
        let durationColumn = column("duration")
        var missing: [String] = []
        if startDate == nil { missing.append("Start date") }
        if startTime == nil { missing.append("Start time") }
        if (endDate == nil || endTime == nil) && durationColumn == nil {
            missing.append(endDate == nil ? "End date" : "End time")
        }
        guard missing.isEmpty, let startDate, let startTime else { throw TogglImportError.missingColumns(missing) }

        let project = column("project")
        let client = column("client")
        let description = column("description")
        let billable = column("billable")
        let tags = column("tags")

        var entries: [TogglEntry] = []
        var projectNames: [String] = []
        var seenProjects: Set<String> = []
        var skipped = 0
        var warnings: [String] = []
        var omittedWarnings = 0
        func warn(_ text: String) {
            if warnings.count < maxWarnings { warnings.append(text) } else { omittedWarnings += 1 }
        }

        for (offset, row) in rows.dropFirst().enumerated() {
            let lineNumber = offset + 2
            func value(_ index: Int?) -> String? {
                guard let index, index < row.count else { return nil }
                let trimmed = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

            guard let start = date(value(startDate), value(startTime), calendar: calendar) else {
                skipped += 1
                warn("Zeile \(lineNumber): Start nicht lesbar – übersprungen.")
                continue
            }
            var end = date(value(endDate), value(endTime), calendar: calendar)
            if end == nil, let seconds = duration(value(durationColumn)) {
                end = start.addingTimeInterval(seconds)
            }
            guard let end else {
                skipped += 1
                warn("Zeile \(lineNumber): Ende nicht lesbar – übersprungen.")
                continue
            }
            guard end >= start else {
                skipped += 1
                warn("Zeile \(lineNumber): Ende liegt vor dem Start – übersprungen.")
                continue
            }

            let name = value(project) ?? noProjectName
            if !seenProjects.contains(name) {
                seenProjects.insert(name)
                projectNames.append(name)
                if name == noProjectName {
                    warn("Einträge ohne Projekt werden „\(noProjectName)“ zugeordnet.")
                }
            }
            entries.append(TogglEntry(
                projectName: name,
                client: value(client),
                description: value(description),
                isBillable: value(billable).map(isYes),
                start: start,
                end: end,
                tags: value(tags).map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } } ?? [],
                line: lineNumber
            ))
        }
        if omittedWarnings > 0 {
            warnings.append("… und \(omittedWarnings) weitere Hinweise.")
        }
        return TogglImportPreview(entries: entries, newProjects: projectNames, skipped: skipped, warnings: warnings)
    }

    // MARK: Bausteine

    /// „2026-10-20“ + „09:05:00“ (auch „9:05“) im Kalender.
    static func date(_ day: String?, _ time: String?, calendar: Calendar) -> Date? {
        guard let day, let time else { return nil }
        let d = day.split(separator: "-").compactMap { Int($0) }
        let t = time.split(separator: ":").compactMap { Int($0) }
        guard d.count == 3, (2...3).contains(t.count),
              (1...12).contains(d[1]), (1...31).contains(d[2]),
              (0...23).contains(t[0]), (0...59).contains(t[1]), t.count == 2 || (0...59).contains(t[2])
        else { return nil }
        var components = DateComponents()
        components.year = d[0]
        components.month = d[1]
        components.day = d[2]
        components.hour = t[0]
        components.minute = t[1]
        components.second = t.count == 3 ? t[2] : 0
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == d[2]  // 31.02. o. ä. nicht stillschweigend verschieben
        else { return nil }
        return date
    }

    /// „01:30:00“ → 5400 s (Stunden auch mehrstellig).
    static func duration(_ text: String?) -> TimeInterval? {
        guard let parts = text?.split(separator: ":").map({ Int($0) }), parts.count == 3,
              let h = parts[0], let m = parts[1], let s = parts[2], h >= 0, (0...59).contains(m), (0...59).contains(s)
        else { return nil }
        return TimeInterval(h * 3600 + m * 60 + s)
    }

    static func isYes(_ text: String) -> Bool {
        ["yes", "ja", "true", "1"].contains(text.lowercased())
    }
}

extension AppDatabase {
    /// Vorschlag für das Mapping: Toggl-Projekt → vorhandenes Projekt mit gleichem Namen
    /// (Groß-/Kleinschreibung egal, Archiv eingeschlossen), sonst `nil` (= neu anlegen).
    public func suggestedTogglMapping(for preview: TogglImportPreview) throws -> [String: UUID?] {
        let projects = try allProjects()
        var mapping: [String: UUID?] = [:]
        for name in preview.newProjects {
            let match = projects.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            mapping[name] = .some(match?.id)
        }
        return mapping
    }

    /// Speichert die Einträge der Vorschau in einer Transaktion und gibt die Zahl der neu
    /// angelegten Einträge zurück.
    ///
    /// - Parameters:
    ///   - projectMapping: Toggl-Projektname → vorhandenes Projekt. `nil` oder fehlender Schlüssel:
    ///     neues Projekt anlegen – gibt es schon eines mit genau diesem Namen (Groß-/Kleinschreibung
    ///     egal), wird stattdessen dieses verwendet, damit ein erneuter Import keine Doppel erzeugt.
    ///   - markAsBusiness: Art (und Abrechenbarkeit) neu angelegter Projekte.
    /// - Dubletten: Ein Eintrag wird übersprungen, wenn es im Zielprojekt schon einen Eintrag mit
    ///   gleichem Start und Ende (±1 s) gibt – auch innerhalb derselben Datei.
    /// - Abrechenbar: Weicht Toggls „Billable“ vom Projekt ab, bekommt der Eintrag einen eigenen
    ///   Wert, sonst erbt er (`nil`). Die Toggl-Beschreibung landet in der Notiz (`nextStep`).
    /// - Throws: `TaktError.projectNotFound`, wenn das Mapping auf ein unbekanntes Projekt zeigt.
    @discardableResult
    public func importToggl(
        _ preview: TogglImportPreview,
        projectMapping: [String: UUID?],
        markAsBusiness: Bool
    ) throws -> Int {
        try writer.write { db in
            var projects = try Project.fetchAll(db)
            var targets: [String: Project] = [:]
            var nextSortOrder = (projects.map(\.sortOrder).max() ?? -1) + 1

            func target(for name: String, client: String?) throws -> Project {
                if let cached = targets[name] { return cached }
                let project: Project
                if case let .some(.some(id)) = projectMapping[name] {
                    guard let existing = projects.first(where: { $0.id == id }) else {
                        throw TaktError.projectNotFound
                    }
                    project = existing
                } else if let existing = projects.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                    project = existing
                } else {
                    let created = Project(
                        name: name,
                        colorHex: ProjectPalette.next(after: projects.filter { !$0.isArchived }.map(\.colorHex)),
                        isBusiness: markAsBusiness,
                        sortOrder: nextSortOrder,
                        client: client
                    )
                    try created.insert(db)
                    nextSortOrder += 1
                    projects.append(created)
                    project = created
                }
                targets[name] = project
                return project
            }

            var inserted = 0
            for item in preview.entries {
                let project = try target(for: item.projectName, client: item.client)
                let startedAt = TimeEntry.Columns.startedAt
                let endedAt = TimeEntry.Columns.endedAt
                let duplicate = try TimeEntry
                    .filter(TimeEntry.Columns.projectId == project.id)
                    .filter(startedAt >= item.start.databaseTime - 1 && startedAt <= item.start.databaseTime + 1)
                    .filter(endedAt >= item.end.databaseTime - 1 && endedAt <= item.end.databaseTime + 1)
                    .fetchCount(db) > 0
                if duplicate { continue }

                let entry = TimeEntry(
                    projectId: project.id,
                    startedAt: item.start,
                    endedAt: item.end,
                    nextStep: Self.normalizedNote(item.description),
                    isBillable: item.isBillable.flatMap { $0 == project.isBillable ? nil : $0 },
                    updatedAt: .now
                )
                try entry.insert(db)
                inserted += 1
            }
            return inserted
        }
    }
}
