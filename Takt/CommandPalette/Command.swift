import Foundation
import SwiftUI

// Befehlspalette (⌘K): Datenmodell, unscharfe Suche, zuletzt genutzte Befehle.
// Bewusst ohne Store- und TaktCore-Abhängigkeit, damit Palette und Suche auch im
// Render-Harness laufen; die Befehle selbst baut `CommandRegistry`.

/// Gruppen der Trefferliste in Standard-Reihenfolge.
enum PaletteGroup: Int, CaseIterable, Comparable {
    /// Nur ohne Suchtext: zuletzt genutzte Befehle (eigene Gruppe oben).
    case recent
    case timer, projects, navigation, reports, export, settings, quickEntry

    var title: String {
        switch self {
        case .recent: "Zuletzt"
        case .timer: "Timer"
        case .projects: "Projekte"
        case .navigation: "Navigation"
        case .reports: "Berichte"
        case .export: "Export"
        case .settings: "Einstellungen"
        case .quickEntry: "Schnelleingabe"
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Rückfrage vor dem Ausführen (z. B. Archivieren).
struct CommandConfirmation {
    let title: String
    let message: String
    let actionTitle: String
}

/// Ein Befehl der Palette.
struct Command: Identifiable {
    /// Stabile Kennung (für „Zuletzt genutzt“), z. B. "nav.today", "project.start.<UUID>".
    let id: String
    var title: String
    var subtitle: String?
    var group: PaletteGroup
    /// Zusätzliche Suchbegriffe (Synonyme, englische Wörter).
    var keywords: [String] = []
    /// SF Symbol; wird durch den Farbpunkt ersetzt, wenn `colorHex` gesetzt ist.
    var icon: String
    /// Projektfarbe als Farbpunkt statt Symbol.
    var colorHex: String?
    /// Kleine Kapsel rechts, z. B. „Business“ / „Privat“.
    var badge: String?
    /// Ohne Suchtext anzeigen? (Archivieren und Einstellungs-Reiter erst bei Suche.)
    var showsWhenEmpty = true
    /// Zuschlag beim Ranking (negativ = weiter unten).
    var priority: Double = 0
    /// Nicht in „Zuletzt genutzt“ aufnehmen (Schnelleingabe-Treffer).
    var isTransient = false
    var confirmation: CommandConfirmation?
    var perform: () -> Void
}

// MARK: - Suche

/// Unscharfe Suche: Wortanfang, Teilwort, Anfangsbuchstaben, Buchstabenfolge –
/// ohne Groß-/Kleinschreibung und Akzente. Mehrere Wörter müssen alle passen.
enum CommandMatcher {
    /// Punktzahl für `query` gegen den Befehl; `nil`, wenn er nicht passt.
    static func score(_ query: String, _ command: Command) -> Double? {
        let tokens = normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return 0 }
        let titleWords = words(command.title)
        let title = normalize(command.title)
        let initials = String(titleWords.compactMap(\.first))
        let compact = titleWords.joined()
        let keywordWords = command.keywords.flatMap(words)
        let subtitleWords = command.subtitle.map(words) ?? []

        var total = 0.0
        for token in tokens {
            guard let value = tokenScore(token, title: title, titleWords: titleWords, initials: initials,
                                         compact: compact, keywordWords: keywordWords,
                                         subtitleWords: subtitleWords) else { return nil }
            total += value
        }
        return total + command.priority
    }

    private static func tokenScore(_ token: String, title: String, titleWords: [String], initials: String,
                                   compact: String, keywordWords: [String], subtitleWords: [String]) -> Double? {
        if let index = titleWords.firstIndex(where: { $0.hasPrefix(token) }) {
            let exact = titleWords[index] == token ? 8.0 : 0
            return (index == 0 ? 100 : 92) + exact
        }
        if token.count >= 2, initials.hasPrefix(token) { return 80 }
        if keywordWords.contains(where: { $0.hasPrefix(token) }) { return 70 }
        // Ab hier nur mit mindestens zwei Zeichen, sonst passt fast alles.
        guard token.count >= 2 else { return nil }
        if title.contains(token) { return 60 }
        if subtitleWords.contains(where: { $0.hasPrefix(token) }) { return 50 }
        if keywordWords.contains(where: { $0.contains(token) }) { return 45 }
        // Buchstabenfolge nur dicht beieinander („wchn“ → Woche), sonst passt fast alles.
        if token.count >= 3, let gaps = subsequenceGaps(token, in: compact), gaps <= max(2, token.count - 1) {
            return 35 - Double(gaps) * 3
        }
        return nil
    }

    /// Anzahl übersprungener Zeichen, wenn `token` als Buchstabenfolge in `text` steckt.
    private static func subsequenceGaps(_ token: String, in text: String) -> Int? {
        var gaps = 0
        var started = false
        var iterator = token.makeIterator()
        var next = iterator.next()
        for character in text {
            guard let wanted = next else { break }
            if character == wanted {
                started = true
                next = iterator.next()
            } else if started {
                gaps += 1
            }
        }
        return next == nil ? gaps : nil
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .lowercased()
    }

    /// Wörter aus Buchstaben und Ziffern („Starten: Kunden-Workshop“ → starten, kunden, workshop).
    static func words(_ text: String) -> [String] {
        normalize(text)
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
    }
}

// MARK: - Trefferliste

/// Abschnitt der Trefferliste.
struct CommandSection: Identifiable {
    let group: PaletteGroup
    var commands: [Command]
    var id: PaletteGroup { group }
}

enum CommandRanking {
    /// Höchstens so viele zuletzt genutzte Befehle.
    static let recentLimit = 5

    /// Abschnitte für Suchtext `query`. Ohne Suchtext: „Zuletzt“, dann alle Gruppen in
    /// Standard-Reihenfolge. Mit Suchtext: Schnelleingabe-Treffer zuerst, dann Gruppen nach
    /// bestem Treffer, zuletzt genutzte Befehle mit Zuschlag.
    static func sections(query: String, commands: [Command], suggestions: [Command], recentIDs: [String]) -> [CommandSection] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            let byId = Dictionary(commands.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let recents = recentIDs.compactMap { byId[$0] }.prefix(recentLimit)
            let recentSet = Set(recents.map(\.id))
            var sections: [CommandSection] = []
            if !recents.isEmpty {
                sections.append(CommandSection(group: .recent, commands: Array(recents)))
            }
            for group in PaletteGroup.allCases where group != .recent {
                let items = commands.filter { $0.group == group && $0.showsWhenEmpty && !recentSet.contains($0.id) }
                if !items.isEmpty { sections.append(CommandSection(group: group, commands: items)) }
            }
            return sections
        }

        var scored: [(command: Command, score: Double, order: Int)] = []
        for (order, command) in commands.enumerated() {
            guard var score = CommandMatcher.score(trimmed, command) else { continue }
            if let rank = recentIDs.firstIndex(of: command.id), rank < recentLimit {
                score += Double(recentLimit - rank) * 3
            }
            scored.append((command, score, order))
        }
        var groups: [PaletteGroup: [(command: Command, score: Double, order: Int)]] = [:]
        for item in scored { groups[item.command.group, default: []].append(item) }

        var sections = groups.map { group, items -> (CommandSection, Double) in
            let sorted = items.sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
            return (CommandSection(group: group, commands: sorted.map(\.command)), sorted.first?.score ?? 0)
        }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.group < $1.0.group }
        .map(\.0)

        // Schnelleingabe-Treffer stehen immer ganz oben.
        if !suggestions.isEmpty {
            if let index = sections.firstIndex(where: { $0.group == .quickEntry }) {
                let existing = sections.remove(at: index)
                sections.insert(CommandSection(group: .quickEntry, commands: suggestions + existing.commands), at: 0)
            } else {
                sections.insert(CommandSection(group: .quickEntry, commands: suggestions), at: 0)
            }
        }
        return sections
    }
}

// MARK: - Zuletzt genutzt

/// Zuletzt genutzte Befehle (Kennungen, neueste zuerst) in `UserDefaults`.
enum CommandRecents {
    private static let key = "commandPalette.recentCommands"

    static func load(_ defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    static func record(_ id: String, _ defaults: UserDefaults = .standard) {
        var ids = load(defaults).filter { $0 != id }
        ids.insert(id, at: 0)
        // Etwas mehr aufheben als angezeigt: verschwundene Befehle (z. B. „Stoppen“) rücken nach.
        defaults.set(Array(ids.prefix(12)), forKey: key)
    }
}

// MARK: - Öffnen von außen

/// Anforderung „Palette öffnen“ aus der Menüleiste. Ist das Hauptfenster noch nicht da,
/// liest `MainView` die Anforderung beim Erscheinen.
@MainActor
enum CommandPaletteRequest {
    static let notification = Notification.Name("dev.eremiya.takt.openCommandPalette")
    private static var isPending = false

    static func post() {
        isPending = true
        NotificationCenter.default.post(name: notification, object: nil)
    }

    /// `true`, wenn eine Anforderung offen war (und setzt sie zurück).
    static func consume() -> Bool {
        defer { isPending = false }
        return isPending
    }
}
