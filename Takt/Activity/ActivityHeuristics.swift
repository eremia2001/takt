import Foundation

// Reine Heuristiken der Aktivitäts-Erkennung: Fenstertitel zerlegen, Repository finden,
// Projekt raten. Bewusst nur Foundation (kein AppKit, kein Store), damit sich alles isoliert
// testen lässt – auch per `swiftc` außerhalb der App.

/// Wie eine App ihren Fenstertitel aufbaut; bestimmt, welcher Titelteil zuerst als Repo-Name gilt.
enum ActivityAppFamily: Equatable, Sendable {
    /// „datei — repo“ (VS Code, Cursor, Windsurf, Sublime Text).
    case fileFirstEditor
    /// „repo — datei“ (Xcode, Zed, JetBrains, Nova).
    case projectFirstEditor
    /// „~/dev/takt — zsh“ oder „takt — -zsh — 80×24“ (Terminal, iTerm, Ghostty …).
    case terminal
    /// Seitentitel ohne Bezug zu Ordnern – keine Repo-Erkennung per Name.
    case browser
    /// Alles andere: nur der Titelteil nach „—“/„–“ wird als Repo-Name versucht.
    case other

    static func of(bundleID: String) -> ActivityAppFamily {
        let id = bundleID.lowercased()
        if fileFirstEditors.contains(id) { return .fileFirstEditor }
        if projectFirstEditors.contains(id) || id.hasPrefix("com.jetbrains.") { return .projectFirstEditor }
        if terminals.contains(id) { return .terminal }
        if browsers.contains(id) { return .browser }
        return .other
    }

    /// Editor oder Terminal: Hier lohnt `kAXDocumentAttribute` und die Titel-Zerlegung.
    var isDeveloperTool: Bool {
        switch self {
        case .fileFirstEditor, .projectFirstEditor, .terminal: true
        case .browser, .other: false
        }
    }

    private static let fileFirstEditors: Set<String> = [
        "com.microsoft.vscode", "com.microsoft.vscodeinsiders", "com.vscodium",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.exafunction.windsurf",
        "com.sublimetext.4", "com.sublimetext.3",
    ]
    private static let projectFirstEditors: Set<String> = [
        "com.apple.dt.xcode", "dev.zed.zed", "dev.zed.zed-preview",
        "com.google.android.studio", "com.panic.nova",
    ]
    private static let terminals: Set<String> = [
        "com.apple.terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "dev.warp.warp-stable", "net.kovidgoyal.kitty", "io.alacritty", "org.alacritty",
        "com.github.wez.wezterm",
    ]
    private static let browsers: Set<String> = [
        "com.apple.safari", "com.apple.safaritechnologypreview", "com.google.chrome",
        "com.google.chrome.canary", "org.mozilla.firefox", "company.thebrowser.browser",
        "com.brave.browser", "com.microsoft.edgemac", "com.operasoftware.opera",
        "com.vivaldi.vivaldi", "app.zen-browser.zen", "org.chromium.chromium",
    ]
}

enum ActivityHeuristics {
    // MARK: Ignorierte Apps

    /// Apps, die keine Arbeit an einem Projekt anzeigen: Sie unterbrechen nichts und werden
    /// nicht gespeichert. Browser sind bewusst **nicht** dabei (Regeln „Fenstertitel enthält“).
    static let ignoredBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.systempreferences",      // Systemeinstellungen
        "com.apple.settings.privacysecurity.extension",
        "com.apple.loginwindow",
        "com.apple.screensaver.engine",
        "com.apple.notificationcenterui",
        "com.apple.spotlight",
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.securityagent",
        "com.apple.music",                   // Musik
        "com.spotify.client",
        "dev.eremiya.takt",                  // Takt selbst
    ]

    static func isIgnored(bundleID: String, ownBundleID: String? = nil) -> Bool {
        let id = bundleID.lowercased()
        if let ownBundleID, id == ownBundleID.lowercased() { return true }
        return ignoredBundleIDs.contains(id)
    }

    // MARK: Titel zerlegen

    /// Trennzeichen zwischen Titelteilen, stärkste zuerst. Der Bindestrich zählt nur mit
    /// Leerzeichen davor und danach („takt - Visual Studio Code“).
    static let titleSeparators = [" — ", " – ", " - ", " | "]

    /// App-Namen, die als Titelteil nichts über das Repository sagen.
    private static let appNameParts: Set<String> = [
        "visual studio code", "code", "cursor", "windsurf", "vscodium", "xcode", "zed",
        "sublime text", "nova", "terminal", "iterm", "iterm2", "ghostty", "warp", "kitty",
        "alacritty", "wezterm", "intellij idea", "webstorm", "pycharm", "android studio",
    ]

    /// Shells und typische Vordergrundprozesse im Terminal-Titel.
    private static let shellParts: Set<String> = [
        "zsh", "-zsh", "bash", "-bash", "fish", "-fish", "sh", "login", "tmux", "screen", "ssh",
        "vim", "nvim", "less", "man", "top", "htop", "node", "python", "python3", "ruby",
        "claude", "codex", "git", "npm", "pnpm", "yarn", "make", "swift", "xcodebuild",
    ]

    /// Teile eines Fenstertitels, bereinigt: Markierungen ungespeicherter Änderungen („●“),
    /// Zusätze wie „[SSH: host]“ oder „(Workspace)“, Fenstergrößen („80×24“), Shell- und
    /// App-Namen fallen weg. Pfade in eckigen Klammern (JetBrains „takt [~/dev/takt]“) bleiben
    /// als eigener Teil erhalten.
    static func titleParts(_ title: String) -> [String] {
        var parts = [title]
        for separator in titleSeparators {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        var result: [String] = []
        for raw in parts {
            var part = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // Markierungen ungespeicherter Änderungen.
            while let first = part.first, "●•*◆".contains(first) {
                part = String(part.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            while let last = part.last, "●•*".contains(last) {
                part = String(part.dropLast()).trimmingCharacters(in: .whitespaces)
            }
            // Eckige Klammern: Pfade herausziehen, alles andere („[SSH: host]“) verwerfen.
            for bracket in bracketContents(of: part, open: "[", close: "]") {
                let inner = bracket.trimmingCharacters(in: .whitespaces)
                if looksLikePath(inner) { result.append(inner) }
                part = part.replacingOccurrences(of: "[\(bracket)]", with: "")
            }
            // Runde Klammern am Ende: „(Workspace)“, „(zsh)“, „(main)“.
            if part.hasSuffix(")"), let open = part.lastIndex(of: "("), open > part.startIndex {
                part = String(part[..<open])
            }
            part = part.trimmingCharacters(in: .whitespaces)
            guard !part.isEmpty else { continue }
            let lower = part.lowercased()
            if appNameParts.contains(lower) || shellParts.contains(lower) { continue }
            if isWindowSize(lower) { continue }
            result.append(part)
        }
        return result
    }

    /// Pfade im Titel: Teile, die mit `~` oder `/` beginnen, auch nach „user@host: “.
    static func pathCandidates(in title: String) -> [String] {
        titleParts(title).compactMap { part in
            if looksLikePath(part) { return part }
            // „eremiya@mac: ~/dev/takt“ (iTerm, Shell-Prompt im Titel).
            if let colon = part.range(of: ": ") {
                let tail = part[colon.upperBound...].trimmingCharacters(in: .whitespaces)
                if looksLikePath(tail) { return tail }
            }
            if part.hasSuffix(":"), looksLikePath(String(part.dropLast())) { return String(part.dropLast()) }
            return nil
        }
    }

    /// Titelteile, die als Ordnername eines Repositorys in Frage kommen – in der Reihenfolge,
    /// in der die App-Familie das Projekt typischerweise nennt. Pfade fehlen hier.
    static func nameCandidates(in title: String, family: ActivityAppFamily) -> [String] {
        let parts = titleParts(title).filter { !looksLikePath($0) && !$0.contains(": ") }
        switch family {
        case .fileFirstEditor: return parts.reversed()
        case .projectFirstEditor, .terminal: return parts
        case .other: return Array(parts.dropFirst())
        case .browser: return []
        }
    }

    // MARK: Repository finden

    /// Ermittelt den Repository-Ordner (normalisiert) aus Dokumentpfad und Fenstertitel:
    /// 1. `documentPath` (`kAXDocumentAttribute`, z. B. Xcode-Datei oder Terminal-Ordner),
    /// 2. Pfade im Titel („~/dev/takt — zsh“),
    /// 3. Titelteile als Ordnername gegen den `index` (Ordner mit `.git` unter `~/dev`).
    /// Bei 1 und 2 wird bis zum nächsten Ordner mit `.git` hochgelaufen.
    static func detectRepo(
        bundleID: String,
        windowTitle: String?,
        documentPath: String?,
        index: RepoIndex,
        home: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> String? {
        let family = ActivityAppFamily.of(bundleID: bundleID)
        if let documentPath, let path = documentURLPath(documentPath),
           let root = repoRoot(containing: path, home: home, fileManager: fileManager) {
            return root
        }
        guard let windowTitle, !windowTitle.isEmpty, family != .browser else { return nil }
        for candidate in pathCandidates(in: windowTitle) {
            if let root = repoRoot(containing: candidate, home: home, fileManager: fileManager) { return root }
        }
        for name in nameCandidates(in: windowTitle, family: family) {
            if let root = index.repo(named: name) { return root }
        }
        return nil
    }

    /// `file://`-URL oder Pfad → Pfad; sonst `nil`.
    static func documentURLPath(_ document: String) -> String? {
        let trimmed = document.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("file://") { return URL(string: trimmed)?.path }
        return looksLikePath(trimmed) ? trimmed : nil
    }

    /// Läuft von `path` (Datei oder Ordner) aufwärts bis zum ersten Ordner mit `.git`
    /// (Ordner oder Datei – Worktrees, Submodule). Nicht existierende Pfadteile werden
    /// übersprungen. Das Benutzerverzeichnis selbst und `/` gelten nie als Repository
    /// (Dotfiles-Repos), und es geht nicht über das Benutzerverzeichnis hinaus.
    static func repoRoot(containing path: String, home: String, fileManager: FileManager = .default) -> String? {
        guard var current = normalize(path, home: home) else { return nil }
        let homePath = normalize(home, home: home) ?? home
        var isDirectory: ObjCBool = false
        // Zum ersten existierenden Element hochlaufen; eine Datei → ihr Ordner.
        while !fileManager.fileExists(atPath: current, isDirectory: &isDirectory) {
            current = (current as NSString).deletingLastPathComponent
            if current == "/" || current.isEmpty { return nil }
        }
        if !isDirectory.boolValue { current = (current as NSString).deletingLastPathComponent }
        while current != "/" && current != homePath && !current.isEmpty {
            if fileManager.fileExists(atPath: (current as NSString).appendingPathComponent(".git")) {
                return current
            }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// `~` aufgelöst, `.`/`..` und abschließender `/` entfernt; Groß-/Kleinschreibung bleibt.
    static func normalize(_ path: String, home: String = NSHomeDirectory()) -> String? {
        var raw = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if raw.hasPrefix("file://"), let url = URL(string: raw) { raw = url.path }
        if raw == "~" { raw = home } else if raw.hasPrefix("~/") { raw = home + raw.dropFirst(1) }
        guard raw.hasPrefix("/") else { return nil }
        // Bewusst nicht `standardizingPath`: Das entfernt `/private` nur bei existierenden Pfaden,
        // dann passen Vergleiche beim Hochlaufen nicht mehr zusammen.
        var parts: [Substring] = []
        for component in raw.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(component)
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    /// Kurzform für die Anzeige: Benutzerverzeichnis als `~`.
    static func abbreviate(_ path: String, home: String = NSHomeDirectory()) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    // MARK: Projekt raten

    /// Projekt zu einem Repository-Namen, wenn keine Regel greift: Namen ohne Groß-/Kleinschreibung,
    /// Akzente, Bindestriche, Unterstriche, Punkte und Leerzeichen verglichen. Zuerst Gleichheit,
    /// dann Teiltext in beide Richtungen (kürzerer Name mindestens 4 Zeichen); bei mehreren
    /// Treffern gewinnt der längste Projektname, bei Gleichstand die Projektreihenfolge.
    static func guessProject(repoName: String, projects: [(id: UUID, name: String)]) -> UUID? {
        let repo = fold(repoName)
        guard !repo.isEmpty else { return nil }
        let folded = projects.map { (id: $0.id, name: fold($0.name)) }.filter { !$0.name.isEmpty }
        if let exact = folded.first(where: { $0.name == repo }) { return exact.id }
        var best: (id: UUID, length: Int)?
        for project in folded {
            let shorter = min(project.name.count, repo.count)
            guard shorter >= 4, repo.contains(project.name) || project.name.contains(repo) else { continue }
            if best == nil || project.name.count > best!.length { best = (project.id, project.name.count) }
        }
        return best?.id
    }

    /// Vergleichsform: klein, ohne Akzente, nur Buchstaben und Ziffern.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    // MARK: Hilfen

    static func looksLikePath(_ text: String) -> Bool {
        text == "~" || text.hasPrefix("~/") || (text.hasPrefix("/") && text.count > 1)
    }

    /// „80×24“, „120x40“.
    private static func isWindowSize(_ text: String) -> Bool {
        let pieces = text.split(whereSeparator: { $0 == "×" || $0 == "x" })
        return pieces.count == 2 && pieces.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    private static func bracketContents(of text: String, open: Character, close: Character) -> [String] {
        var result: [String] = []
        var current: String?
        for character in text {
            if character == open {
                current = ""
            } else if character == close, let value = current {
                result.append(value)
                current = nil
            } else if current != nil {
                current?.append(character)
            }
        }
        return result
    }
}

/// Ordner mit `.git` direkt unter den Projektwurzeln (`~/dev`, außerdem `~/Developer`,
/// `~/Projects`, `~/code`, sofern vorhanden) – für den Abgleich von Titelteilen mit Repo-Namen.
struct RepoIndex: Sendable, Equatable {
    /// Ordnername (klein) → Pfad.
    private(set) var byName: [String: String] = [:]
    /// Gefaltete Namen (ohne Bindestriche usw.) → Pfad; nur eindeutige.
    private(set) var byFoldedName: [String: String] = [:]

    static let empty = RepoIndex()

    static func defaultRoots(home: String = NSHomeDirectory()) -> [String] {
        ["dev", "Developer", "Projects", "code"].map { (home as NSString).appendingPathComponent($0) }
    }

    init() {}

    init(roots: [String], fileManager: FileManager = .default) {
        var folded: [String: [String]] = [:]
        for root in roots {
            guard let children = try? fileManager.contentsOfDirectory(atPath: root) else { continue }
            for child in children.sorted() where !child.hasPrefix(".") {
                let path = (root as NSString).appendingPathComponent(child)
                guard fileManager.fileExists(atPath: (path as NSString).appendingPathComponent(".git")) else { continue }
                let key = child.lowercased()
                if byName[key] == nil { byName[key] = path }
                folded[ActivityHeuristics.fold(child), default: []].append(path)
            }
        }
        byFoldedName = folded.compactMapValues { $0.count == 1 ? $0[0] : nil }
    }

    /// Repository zu einem Titelteil: Ordnername gleich (ohne Groß-/Kleinschreibung), sonst
    /// gefaltet gleich („EventBuster App“ ↔ `eventbuster-app`).
    func repo(named name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let path = byName[trimmed.lowercased()] { return path }
        let folded = ActivityHeuristics.fold(trimmed)
        guard folded.count >= 3 else { return nil }
        return byFoldedName[folded]
    }

    var count: Int { byName.count }
}
