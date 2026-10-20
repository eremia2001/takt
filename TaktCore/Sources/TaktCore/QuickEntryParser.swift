import Foundation

// MARK: - Ergebnis

/// Ergebnis der Schnelleingabe: entweder ein fertiger Eintrag (`end != nil`) oder ein Timer-Start
/// (`isRunningStart`, `end == nil`).
public struct QuickEntry: Hashable, Sendable {
    /// Gefundenes Projekt (bei Erfolg immer gesetzt).
    public var projectId: UUID?
    public var projectName: String
    /// Beginn. Beim bloßen Projektnamen „jetzt“ zum Zeitpunkt des Parsens.
    public var start: Date
    /// Ende; `nil` bei einem Timer-Start.
    public var end: Date?
    /// Tag ohne `#`, normalisiert wie `TimeEntry.normalizedTag`.
    public var tag: String?
    /// Restlicher Text, landet als Notiz im Eintrag (`TimeEntry.nextStep`).
    public var note: String?
    /// `true` = Timer starten statt fertigen Eintrag anlegen.
    public var isRunningStart: Bool

    public init(
        projectId: UUID?,
        projectName: String,
        start: Date,
        end: Date?,
        tag: String?,
        note: String?,
        isRunningStart: Bool
    ) {
        self.projectId = projectId
        self.projectName = projectName
        self.start = start
        self.end = end
        self.tag = tag
        self.note = note
        self.isRunningStart = isRunningStart
    }

    /// Dauer eines fertigen Eintrags, `nil` bei einem Timer-Start.
    public var duration: TimeInterval? { end.map { $0.timeIntervalSince(start) } }
}

public enum QuickEntryError: Error, Equatable, Sendable, LocalizedError {
    /// Nichts eingegeben.
    case empty
    /// Nur Zeit/Tag/Tag-Angabe, aber kein Projekt.
    case missingProject
    /// Kein Projekt passt zum Text.
    case unknownProject(String)
    /// Mehrere Projekte passen gleich gut.
    case ambiguousProject([Project])
    /// Ende vor Start und nicht als plausible Spanne über Mitternacht (< 12 h) deutbar,
    /// oder Start gleich Ende.
    case invalidTimeRange
    /// Für einen anderen Tag als heute fehlen Start und Ende (Dauer oder bloßer Start reichen nicht).
    case missingTime
    /// Ein bloßer Startzeitpunkt („Website 22:00“) liegt in der Zukunft.
    case startInFuture

    public var errorDescription: String? {
        switch self {
        case .empty:
            "Bitte ein Projekt eingeben, z. B. „Kundenportal 9-10:30 #meeting Notiz“."
        case .missingProject:
            "Es fehlt das Projekt."
        case .unknownProject(let text):
            "Kein Projekt passt zu „\(text)“."
        case .ambiguousProject(let projects):
            "Mehrere Projekte passen: " + projects.map(\.name).joined(separator: ", ") + "."
        case .invalidTimeRange:
            "Das Ende liegt vor dem Start."
        case .missingTime:
            "Für einen anderen Tag bitte Start und Ende angeben, z. B. „gestern 20-21“."
        case .startInFuture:
            "Der Start liegt in der Zukunft."
        }
    }
}

// MARK: - Parser

/// Liest Eingaben wie „Kundenportal 9:00-10:30 Review“ oder „kunden 9-10:30 #meeting Standup“.
///
/// Grammatik (tolerant): `[<Tag>] <Projekt> [<Tag>] [<Zeit>] [<Tag>] [#Tag] [Notiz…]`, wobei das
/// Projekt auch hinter der Zeit stehen darf („Mo 9-11 Kundenportal“). Zeitangaben:
/// - Spanne: `9-10:30`, `9:00 - 10:30`, `14:00 bis 15:15`, `von 9 bis 11 Uhr`, `9.30-11`;
///   Ende vor Start gilt als über Mitternacht, wenn die Spanne dann unter 12 h liegt.
/// - Dauer bis jetzt: `1h30`, `1h`, `45m`, `90min`, `1,5h`, `1:30h`, `2 Std`, `1h 15m`.
/// - Start ohne Ende (Timer seit …): `9:30`, `ab 9`, `seit 9:30`, `9 Uhr`.
/// - Ohne Zeit: Timer startet jetzt.
/// Tage: `heute`, `gestern`, `vorgestern`, Wochentage (`Mo`, `Montag` … – der letzte solche Tag,
/// heute eingeschlossen), Datum `19.10.` oder `19.10.2026`; am Anfang oder direkt vor/nach der Zeit.
public enum QuickEntryParser {
    /// Höchstdauer einer Spanne über Mitternacht bzw. eines rückdatierten Starts über Mitternacht.
    static let maxOvernight: TimeInterval = 12 * 3600

    public static func parse(
        _ text: String,
        projects: [Project],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Result<QuickEntry, QuickEntryError> {
        let cleaned = text
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
        var words = cleaned.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return .failure(.empty) }

        // 1. Tag (`#meeting`): der erste; ein einzelnes `#` wird ignoriert.
        var tag: String?
        if let index = words.firstIndex(where: { $0.hasPrefix("#") && $0.count > 1 }) {
            tag = TimeEntry.normalizedTag(words[index])
            words.remove(at: index)
        }
        words.removeAll { $0 == "#" }
        guard !words.isEmpty else { return .failure(.missingProject) }

        // 2. Zeitangabe (die erste gefundene) auf zerlegten Teilen, zurückgeführt auf Wörter.
        let pieces = expand(words)
        let spec = findTimeSpec(pieces.map(\.text))
        let specWords: ClosedRange<Int>? = spec.map {
            pieces[$0.range.lowerBound].origin...pieces[$0.range.upperBound - 1].origin
        }

        // 3. Tag: am Anfang oder direkt vor/nach der Zeitangabe.
        var day: Date?
        var dayIndex: Int?
        var candidates = [0]
        if let specWords { candidates += [specWords.lowerBound - 1, specWords.upperBound + 1] }
        for candidate in candidates where words.indices.contains(candidate) && !(specWords?.contains(candidate) ?? false) {
            if let parsed = parseDay(words[candidate], now: now, calendar: calendar) {
                day = parsed
                dayIndex = candidate
                break
            }
        }

        // 4. Wörter vor und nach der Zeitangabe.
        func segment(_ range: Range<Int>, skipping skip: Int?) -> [String] {
            range.filter { $0 != skip }.map { words[$0] }
        }
        let splitStart = specWords?.lowerBound ?? words.count
        let splitEnd = specWords.map { $0.upperBound + 1 } ?? words.count
        var before = segment(0..<splitStart, skipping: dayIndex)
        var after = segment(splitEnd..<words.count, skipping: dayIndex)
        if before.isEmpty, after.isEmpty, dayIndex != nil {
            // Der vermeintliche Tag ist das einzige Wort – dann ist er wohl der Projektname
            // (z. B. ein Projekt „Sonntag“).
            day = nil
            before = segment(0..<splitStart, skipping: nil)
            after = segment(splitEnd..<words.count, skipping: nil)
        }

        // 5. Projekt: längster passender Anfang des Textes vor der Zeit, sonst danach.
        let project: Project
        let noteWords: [String]
        if !before.isEmpty {
            switch resolveProject(before, projects: projects, unknownText: before.joined(separator: " ")) {
            case .success(let (match, rest)):
                project = match
                noteWords = rest + after
            case .failure(let error):
                return .failure(error)
            }
        } else if !after.isEmpty {
            switch resolveProject(after, projects: projects, unknownText: after[0]) {
            case .success(let (match, rest)):
                project = match
                noteWords = rest
            case .failure(let error):
                return .failure(error)
            }
        } else {
            return .failure(.missingProject)
        }
        let note = AppDatabase.normalizedNote(noteWords.joined(separator: " "))

        // 6. Zeiten berechnen.
        let today = calendar.startOfDay(for: now)
        let base = day ?? today
        let isToday = base == today
        func entry(start: Date, end: Date?, running: Bool) -> Result<QuickEntry, QuickEntryError> {
            .success(QuickEntry(
                projectId: project.id, projectName: project.name, start: start, end: end,
                tag: tag, note: note, isRunningStart: running
            ))
        }

        switch spec?.kind {
        case nil:
            guard isToday else { return .failure(.missingTime) }
            return entry(start: now, end: nil, running: true)

        case .duration(let duration):
            guard isToday else { return .failure(.missingTime) }
            return entry(start: now.addingTimeInterval(-duration), end: now, running: false)

        case .start(let clock):
            guard isToday, var start = combine(base, clock, calendar: calendar) else { return .failure(.missingTime) }
            if start > now {
                // Ohne ausdrücklichen Tag kurz nach Mitternacht: „seit 23:00“ meint gestern.
                guard day == nil,
                      let previous = calendar.date(byAdding: .day, value: -1, to: start),
                      now.timeIntervalSince(previous) < maxOvernight
                else { return .failure(.startInFuture) }
                start = previous
            }
            return entry(start: start, end: nil, running: true)

        case .range(let from, let to):
            guard var start = combine(base, from, calendar: calendar),
                  var end = combine(base, to, calendar: calendar)
            else { return .failure(.invalidTimeRange) }
            if end <= start {
                guard end < start,
                      let nextEnd = calendar.date(byAdding: .day, value: 1, to: end),
                      nextEnd.timeIntervalSince(start) < maxOvernight
                else { return .failure(.invalidTimeRange) }
                end = nextEnd
                // Ohne ausdrücklichen Tag und noch nicht vorbei: die Nacht von gestern auf heute.
                if day == nil, end > now,
                   let earlierStart = calendar.date(byAdding: .day, value: -1, to: start),
                   let earlierEnd = calendar.date(byAdding: .day, value: -1, to: end) {
                    start = earlierStart
                    end = earlierEnd
                }
            }
            return entry(start: start, end: end, running: false)
        }
    }

    // MARK: Projektsuche

    /// Längster Anfang von `words`, der zu einem Projekt passt; der Rest ist Notiz.
    /// Bei mehreren gleich guten Treffern auf der längsten passenden Länge: mehrdeutig.
    static func resolveProject(
        _ words: [String],
        projects: [Project],
        unknownText: String
    ) -> Result<(Project, [String]), QuickEntryError> {
        for length in stride(from: words.count, through: 1, by: -1) {
            let query = words[0..<length].joined(separator: " ")
            let matches = bestMatches(for: query, in: projects, allowFuzzy: length == 1)
            if matches.count == 1 { return .success((matches[0], Array(words[length...]))) }
            if matches.count > 1 { return .failure(.ambiguousProject(matches)) }
        }
        return .failure(.unknownProject(unknownText))
    }

    /// Projekte mit der höchsten Trefferstufe (leer, wenn keins passt), in der gegebenen Reihenfolge.
    static func bestMatches(for query: String, in projects: [Project], allowFuzzy: Bool) -> [Project] {
        let scored = projects.map { ($0, score(query: query, name: $0.name, allowFuzzy: allowFuzzy)) }
        guard let best = scored.map(\.1).max(), best > 0 else { return [] }
        return scored.filter { $0.1 == best }.map(\.0)
    }

    /// Trefferstufe: 100 gleich, 80 Namensanfang, 60 Wortanfang, 40 Teilwort, 30 ein Tippfehler,
    /// 20 Buchstabenfolge (nur einzelne Wörter ab 3 bzw. 4 Zeichen); 0 = kein Treffer.
    /// Groß-/Kleinschreibung und Akzente zählen nicht.
    static func score(query: String, name: String, allowFuzzy: Bool) -> Int {
        let q = AppDatabase.foldedForSearch(query).trimmingCharacters(in: .whitespaces)
        let n = AppDatabase.foldedForSearch(name).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !n.isEmpty else { return 0 }
        if n == q { return 100 }
        if n.hasPrefix(q) { return 80 }
        let nameWords = n.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if nameWords.contains(where: { $0.hasPrefix(q) }) { return 60 }
        if n.contains(q) { return 40 }
        guard allowFuzzy, !q.contains(" ") else { return 0 }
        if q.count >= 4, editDistance(q, n) <= 1 || nameWords.contains(where: { editDistance(q, $0) <= 1 }) {
            return 30
        }
        if q.count >= 3, isSubsequence(q, of: n) { return 20 }
        return 0
    }

    static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var iterator = haystack.makeIterator()
        return needle.allSatisfy { character in
            while let next = iterator.next() { if next == character { return true } }
            return false
        }
    }

    /// Levenshtein-Abstand (klein genug für Projektnamen).
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }

    // MARK: Zeitangaben

    struct Clock: Hashable {
        var hour: Int
        var minute: Int
    }

    enum TimeSpec: Hashable {
        case range(Clock, Clock)
        case duration(TimeInterval)
        case start(Clock)
    }

    /// Ein Teil eines Wortes nach dem Zerlegen an Bindestrichen, mit Index des Ursprungsworts.
    struct Piece {
        var text: String
        var origin: Int
    }

    /// Zerlegt Wörter wie `9-10:30`, `9:00-` oder `-10:30` in `9`, `-`, `10:30`; alles andere bleibt.
    static func expand(_ words: [String]) -> [Piece] {
        var pieces: [Piece] = []
        for (index, word) in words.enumerated() {
            let parts = word.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let isClockPair = word != "-" && parts.count == 2
                && parts.allSatisfy { $0.isEmpty || parseClock($0, allowBare: true) != nil }
            if isClockPair {
                if !parts[0].isEmpty { pieces.append(Piece(text: parts[0], origin: index)) }
                pieces.append(Piece(text: "-", origin: index))
                if !parts[1].isEmpty { pieces.append(Piece(text: parts[1], origin: index)) }
            } else {
                pieces.append(Piece(text: word, origin: index))
            }
        }
        return pieces
    }

    /// Erste Zeitangabe in den Teilen: Spanne vor Dauer vor bloßem Start, jeweils an derselben Stelle.
    static func findTimeSpec(_ t: [String]) -> (kind: TimeSpec, range: Range<Int>)? {
        for i in t.indices {
            if let found = matchRange(t, at: i) ?? matchDuration(t, at: i) ?? matchStart(t, at: i) {
                return found
            }
        }
        return nil
    }

    private static func lower(_ t: [String], _ i: Int) -> String? {
        t.indices.contains(i) ? t[i].lowercased() : nil
    }

    /// `[von] A [Uhr] (-|bis) B [Uhr]`.
    static func matchRange(_ t: [String], at i: Int) -> (kind: TimeSpec, range: Range<Int>)? {
        var k = i
        if lower(t, k) == "von" { k += 1 }
        guard t.indices.contains(k), let from = parseClock(t[k], allowBare: true) else { return nil }
        k += 1
        if lower(t, k) == "uhr" { k += 1 }
        guard let separator = lower(t, k), separator == "-" || separator == "bis" else { return nil }
        k += 1
        guard t.indices.contains(k), let to = parseClock(t[k], allowBare: true) else { return nil }
        k += 1
        if lower(t, k) == "uhr" { k += 1 }
        return (.range(from, to), i..<k)
    }

    /// Dauer, auch zusammengesetzt aus zwei Angaben („1h 15m“, „1 h 30 min“).
    static func matchDuration(_ t: [String], at i: Int) -> (kind: TimeSpec, range: Range<Int>)? {
        guard let (first, next) = durationPart(t, at: i) else { return nil }
        var total = first
        var end = next
        if let (extra, afterExtra) = durationPart(t, at: end), extra < 3600, first >= 3600 {
            total += extra
            end = afterExtra
        }
        guard total > 0, total <= 24 * 3600 else { return nil }
        return (.duration(total), i..<end)
    }

    /// Eine Dauerangabe ab `i`: Sekunden und Index nach der Angabe.
    private static func durationPart(_ t: [String], at i: Int) -> (TimeInterval, Int)? {
        guard let word = lower(t, i)?.replacingOccurrences(of: ",", with: ".") else { return nil }
        if let seconds = parseDuration(word) { return (seconds, i + 1) }
        // Zahl und Einheit getrennt: „2 Std“, „30 min“.
        if let number = Double(word), number.isFinite, let unit = lower(t, i + 1).flatMap(unitSeconds) {
            return (number * unit, i + 2)
        }
        return nil
    }

    private static func unitSeconds(_ unit: String) -> TimeInterval? {
        switch unit.trimmingCharacters(in: CharacterSet(charactersIn: ".")) {
        case "h", "std", "stunde", "stunden": 3600
        case "m", "min", "minute", "minuten": 60
        default: nil
        }
    }

    /// `1h30`, `1h30m`, `1.5h`, `45m`, `90min`, `1:30h` (bereits klein, Komma → Punkt).
    static func parseDuration(_ word: String) -> TimeInterval? {
        if let match = word.wholeMatch(of: #/(\d{1,2}):(\d{2})h/#),
           let h = Double(match.1), let m = Double(match.2), m < 60 {
            return h * 3600 + m * 60
        }
        if let match = word.wholeMatch(of: #/(\d+(?:\.\d+)?)(?:h|std)(?:(\d{1,2})(?:m|min)?)?/#),
           let h = Double(match.1) {
            let m = match.2.flatMap { Double($0) } ?? 0
            guard m < 60 else { return nil }
            return h * 3600 + m * 60
        }
        if let match = word.wholeMatch(of: #/(\d+)(?:m|min)/#), let m = Double(match.1) {
            return m * 60
        }
        return nil
    }

    /// Bloßer Start: `9:30`, `9 Uhr`, `ab 9`, `seit 9.30`, `um 9`.
    static func matchStart(_ t: [String], at i: Int) -> (kind: TimeSpec, range: Range<Int>)? {
        var k = i
        let hasPreposition = ["ab", "seit", "um"].contains(lower(t, k) ?? "")
        if hasPreposition { k += 1 }
        guard t.indices.contains(k) else { return nil }
        let followedByUhr = lower(t, k + 1) == "uhr"
        // Ohne Präposition oder „Uhr“ nur mit Doppelpunkt – „Version 1.20“ bleibt Text.
        let strict = !hasPreposition && !followedByUhr
        guard let clock = parseClock(t[k], allowBare: !strict, requireColon: strict), clock.hour < 24 else { return nil }
        k += 1
        if followedByUhr { k += 1 }
        return (.start(clock), i..<k)
    }

    /// `9`, `09`, `9:30`, `9.30`, `9uhr`; Stunde 0–24 (24 nur mit :00), Minute 0–59.
    static func parseClock(_ text: String, allowBare: Bool, requireColon: Bool = false) -> Clock? {
        var word = text.lowercased()
        if word.hasSuffix("uhr") { word.removeLast(3) }
        guard let match = word.wholeMatch(of: #/(\d{1,2})(?:([:.])(\d{2}))?/#), let hour = Int(match.1) else { return nil }
        let minute = match.3.flatMap { Int($0) } ?? 0
        if match.3 == nil, !allowBare { return nil }
        if requireColon, match.2 != ":" { return nil }
        guard hour <= 24, minute <= 59, hour < 24 || minute == 0 else { return nil }
        return Clock(hour: hour, minute: minute)
    }

    /// Uhrzeit am Tag `base` (Mitternacht); 24:00 = Mitternacht des Folgetags.
    static func combine(_ base: Date, _ clock: Clock, calendar: Calendar) -> Date? {
        if clock.hour == 24 { return calendar.date(byAdding: .day, value: 1, to: base) }
        return calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: base)
    }

    // MARK: Tage

    private static let weekdays: [String: Int] = [
        "so": 1, "sonntag": 1, "mo": 2, "montag": 2, "di": 3, "dienstag": 3, "mi": 4, "mittwoch": 4,
        "do": 5, "donnerstag": 5, "fr": 6, "freitag": 6, "sa": 7, "samstag": 7,
    ]

    /// Mitternacht des genannten Tags, `nil` wenn das Wort kein Tag ist.
    static func parseDay(_ word: String, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        let lowered = word.lowercased()

        // Datum „19.10.“ / „19.10.2026“ / „19.10.26“ (der Punkt nach dem Monat unterscheidet es von 19.10 Uhr).
        if let match = lowered.wholeMatch(of: #/(\d{1,2})\.(\d{1,2})\.(\d{2}|\d{4})?/#),
           let dayNumber = Int(match.1), let month = Int(match.2) {
            let currentYear = calendar.component(.year, from: today)
            var year = match.3.flatMap { Int($0) } ?? currentYear
            if year < 100 { year += 2000 }
            guard var date = calendar.date(from: DateComponents(year: year, month: month, day: dayNumber)),
                  calendar.component(.day, from: date) == dayNumber
            else { return nil }
            // Ohne Jahr: das letzte solche Datum (nicht in der Zukunft).
            if match.3 == nil, date > today,
               let previous = calendar.date(byAdding: .year, value: -1, to: date) {
                date = previous
            }
            return calendar.startOfDay(for: date)
        }

        let key = lowered.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        switch key {
        case "heute": return today
        case "gestern": return calendar.date(byAdding: .day, value: -1, to: today)
        case "vorgestern": return calendar.date(byAdding: .day, value: -2, to: today)
        default: break
        }
        guard let target = weekdays[key] else { return nil }
        // Der letzte solche Wochentag, heute eingeschlossen.
        let current = calendar.component(.weekday, from: today)
        let back = (current - target + 7) % 7
        return calendar.date(byAdding: .day, value: -back, to: today)
    }
}
