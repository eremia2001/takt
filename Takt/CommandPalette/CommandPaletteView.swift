import SwiftUI

// Befehlspalette (⌘K) als Overlay über dem Hauptfenster, Spotlight-artig oben zentriert.
// Rein darstellend: Befehle, Schnelleingabe-Treffer und Ausführen kommen von außen
// (in der App aus `CommandRegistry`), damit sie auch im Render-Harness läuft.

/// Abgedunkelter Hintergrund plus Palette; Klick daneben schließt.
struct CommandPaletteOverlay: View {
    let commands: [Command]
    /// Schnelleingabe-Treffer für den Suchtext; `hasCommandMatch` = mindestens ein Befehl passt.
    var suggestions: (_ query: String, _ hasCommandMatch: Bool) -> [Command] = { _, _ in [] }
    var recentIDs: [String] = []
    var initialQuery = ""
    var topInset: CGFloat = 64
    var run: (Command) -> Void = { _ in }
    var close: () -> Void = {}

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(scheme == .dark ? 0.38 : 0.16)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .accessibilityHidden(true)
            CommandPaletteView(
                commands: commands,
                suggestions: suggestions,
                recentIDs: recentIDs,
                initialQuery: initialQuery,
                run: run,
                close: close
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.18), radius: 28, y: 12)
            .padding(.top, topInset)
            .padding(.horizontal, 20)
        }
    }
}

struct CommandPaletteView: View {
    let commands: [Command]
    var suggestions: (_ query: String, _ hasCommandMatch: Bool) -> [Command] = { _, _ in [] }
    var recentIDs: [String] = []
    var run: (Command) -> Void = { _ in }
    var close: () -> Void = {}

    @Environment(\.colorScheme) private var scheme
    @State private var query: String
    @State private var selection = 0
    /// Befehl, der auf Bestätigung wartet (Archivieren).
    @State private var pending: Command?
    @FocusState private var isFocused: Bool

    static let width: CGFloat = 600
    static let rowHeight: CGFloat = 36
    static let headerHeight: CGFloat = 26
    /// Höchstens so viele Zeilen sichtbar, der Rest scrollt.
    static let visibleRows = 8

    init(commands: [Command], suggestions: @escaping (String, Bool) -> [Command] = { _, _ in [] },
         recentIDs: [String] = [], initialQuery: String = "",
         run: @escaping (Command) -> Void = { _ in }, close: @escaping () -> Void = {}) {
        self.commands = commands
        self.suggestions = suggestions
        self.recentIDs = recentIDs
        self.run = run
        self.close = close
        _query = State(initialValue: initialQuery)
    }

    private var theme: DesignTheme { DesignTheme(scheme: scheme) }

    private var sections: [CommandSection] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return CommandRanking.sections(query: "", commands: commands, suggestions: [], recentIDs: recentIDs)
        }
        let matched = CommandRanking.sections(query: trimmed, commands: commands, suggestions: [], recentIDs: recentIDs)
        let quick = suggestions(trimmed, !matched.isEmpty)
        guard !quick.isEmpty else { return matched }
        return CommandRanking.sections(query: trimmed, commands: commands, suggestions: quick, recentIDs: recentIDs)
    }

    var body: some View {
        let sections = sections
        let flat = sections.flatMap(\.commands)
        let selected = flat.isEmpty ? nil : min(max(0, selection), flat.count - 1)

        VStack(spacing: 0) {
            field
            Rectangle().fill(theme.hairline).frame(height: 1)
            if let pending {
                confirmation(pending)
            } else if flat.isEmpty {
                emptyState
            } else {
                list(sections: sections, selected: selected)
            }
            Rectangle().fill(theme.hairline).frame(height: 1)
            footer
        }
        .frame(width: Self.width)
        .background(.regularMaterial)
        .background(theme.window.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.16 : 0.08), lineWidth: 1)
        )
        .background { shortcuts }
        .onChange(of: query) {
            selection = 0
            pending = nil
        }
        .onAppear {
            // Erst im nächsten Durchlauf: Das Overlay muss schon im Fenster hängen.
            DispatchQueue.main.async { isFocused = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Befehlspalette")
    }

    // MARK: Suchfeld

    private var field: some View {
        HStack(spacing: 12) {
            Image(systemName: "command")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.secondary)
            TextField(
                "Befehl suchen",
                text: $query,
                prompt: Text("Befehl suchen oder Schnelleingabe …").foregroundStyle(theme.tertiary)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 20, weight: .light))
            .focused($isFocused)
            .onSubmit(submit)
            KeyCap(text: "esc", theme: theme)
        }
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .frame(height: 54)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }

    // MARK: Liste

    private func list(sections: [CommandSection], selected: Int?) -> some View {
        // Höhe aus dem Inhalt, höchstens acht Zeilen (plus Überschriften), darüber scrollen.
        let rows = sections.reduce(0) { $0 + $1.commands.count }
        let contentHeight = CGFloat(rows) * Self.rowHeight + CGFloat(sections.count) * Self.headerHeight + 12
        let maxHeight = CGFloat(Self.visibleRows) * Self.rowHeight + 2 * Self.headerHeight + 12
        var offsets: [Int] = []
        var running = 0
        for section in sections {
            offsets.append(running)
            running += section.commands.count
        }

        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { sectionIndex, section in
                        sectionHeader(section.group)
                        ForEach(Array(section.commands.enumerated()), id: \.element.id) { index, command in
                            let flatIndex = offsets[sectionIndex] + index
                            CommandRow(
                                command: command,
                                index: flatIndex,
                                isSelected: flatIndex == selected,
                                theme: theme
                            )
                            .id(command.id)
                            .onTapGesture { perform(command) }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.never)
            .frame(height: min(contentHeight, maxHeight))
            .onChange(of: selected) {
                guard let selected else { return }
                let flat = sections.flatMap(\.commands)
                guard flat.indices.contains(selected) else { return }
                if selected == 0, let first = sections.first {
                    // Ganz oben auch die erste Überschrift zeigen.
                    proxy.scrollTo("header-\(first.group.rawValue)", anchor: .top)
                } else {
                    proxy.scrollTo(flat[selected].id)
                }
            }
        }
    }

    private func sectionHeader(_ group: PaletteGroup) -> some View {
        Text(group.title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.tertiary)
            .padding(.leading, 20)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, minHeight: Self.headerHeight, maxHeight: Self.headerHeight, alignment: .leading)
            .id("header-\(group.rawValue)")
            .accessibilityAddTraits(.isHeader)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.tertiary)
            Text("Kein Befehl gefunden")
                .foregroundStyle(.secondary)
            Text("·").foregroundStyle(theme.tertiary)
            Text("Schnelleingabe z. B. „Website 1h30“")
                .foregroundStyle(theme.tertiary)
            Spacer(minLength: 0)
        }
        .font(.system(size: 13, weight: .medium))
        .lineLimit(1)
        .padding(.horizontal, 20)
        .frame(height: 52)
    }

    // MARK: Bestätigung

    private func confirmation(_ command: Command) -> some View {
        let info = command.confirmation
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: command.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.orange)
                Text(info?.title ?? command.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            if let message = info?.message {
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button { pending = nil } label: {
                    Text("Abbrechen").frame(minWidth: 70)
                }
                .controlSize(.large)
                Button(role: .destructive) { confirm() } label: {
                    Text(info?.actionTitle ?? "Ausführen").frame(minWidth: 70)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Fußzeile

    private var footer: some View {
        HStack(spacing: 6) {
            if pending != nil {
                hint("↩", "bestätigen")
                dot
                hint("esc", "abbrechen")
            } else {
                hint("↑↓", "auswählen")
                dot
                hint("↩", "ausführen")
                dot
                hint("⌘1–9", "direkt")
            }
            Spacer(minLength: 6)
            Text("⌘K")
                .foregroundStyle(theme.tertiary)
        }
        .font(.system(size: 11.5, weight: .medium))
        .lineLimit(1)
        .padding(.horizontal, 18)
        .frame(height: 32)
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Text(key).foregroundStyle(.secondary)
            Text(text).foregroundStyle(theme.tertiary)
        }
    }

    private var dot: some View {
        Text("·").foregroundStyle(theme.tertiary)
    }

    // MARK: Tastatur

    /// Unsichtbare Knöpfe für ↑ ↓ Esc und ⌘1–9 – greifen vor dem Textfeld (Tastenäquivalente).
    /// Die Aktionen lesen Treffer und Auswahl erst beim Auslösen (nicht beim Zeichnen).
    private var shortcuts: some View {
        ZStack {
            Button("") { move(-1) }
                .keyboardShortcut(.upArrow, modifiers: [])
            Button("") { move(1) }
                .keyboardShortcut(.downArrow, modifiers: [])
            Button("") { cancel() }
                .keyboardShortcut(.cancelAction)
            ForEach(1..<10) { number in
                Button("") {
                    let flat = currentCommands
                    guard pending == nil, flat.indices.contains(number - 1) else { return }
                    perform(flat[number - 1])
                }
                .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    /// Aktuelle Trefferliste (flach, in Anzeigereihenfolge).
    private var currentCommands: [Command] { sections.flatMap(\.commands) }

    private func move(_ delta: Int) {
        let count = currentCommands.count
        guard pending == nil, count > 0 else { return }
        let current = min(max(0, selection), count - 1)
        // Am Ende wieder oben anfangen (und umgekehrt).
        selection = (current + delta + count) % count
    }

    private func cancel() {
        if pending != nil {
            pending = nil
        } else if !query.isEmpty {
            query = ""
        } else {
            close()
        }
    }

    private func submit() {
        if pending != nil {
            confirm()
            return
        }
        let flat = currentCommands
        guard !flat.isEmpty else { return }
        perform(flat[min(max(0, selection), flat.count - 1)])
        // Fokus bleibt im Feld (Enter nimmt ihn sonst weg, falls die Palette offen bleibt).
        isFocused = true
    }

    private func perform(_ command: Command) {
        if command.confirmation != nil {
            pending = command
            isFocused = true
        } else {
            run(command)
        }
    }

    private func confirm() {
        guard let command = pending else { return }
        pending = nil
        run(command)
    }
}

// MARK: - Zeile

private struct CommandRow: View {
    let command: Command
    let index: Int
    let isSelected: Bool
    let theme: DesignTheme

    var body: some View {
        HStack(spacing: 10) {
            leading
                .frame(width: 22, height: 22)
            Text(command.title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(1)
            if let subtitle = command.subtitle {
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            if let badge = command.badge {
                Text(badge)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(theme.tertiary)
                    .padding(.horizontal, 6)
                    .frame(height: 17)
                    .overlay(Capsule().stroke(theme.hairline, lineWidth: 1))
                    .fixedSize()
            }
            trailing
                .frame(minWidth: 28, alignment: .trailing)
        }
        .monospacedDigit()
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .frame(height: CommandPaletteView.rowHeight)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(theme.dark ? 0.26 : 0.14))
            }
        }
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var leading: some View {
        if let hex = command.colorHex {
            ZStack {
                Circle().fill(Color(hex: hex)).frame(width: 9, height: 9)
                if command.icon != "circle.fill" {
                    // Kleines Zeichen unten rechts (z. B. Archivieren, Eintragen).
                    Image(systemName: command.icon)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .offset(x: 8, y: 7)
                }
            }
        } else {
            Image(systemName: command.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if isSelected {
            Image(systemName: "return")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        } else if index < 9 {
            Text("⌘\(index + 1)")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(theme.tertiary)
        }
    }
}

/// Tastenkappe mit Haarlinie, z. B. „esc“.
private struct KeyCap: View {
    let text: String
    let theme: DesignTheme

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.tertiary)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(theme.hairline, lineWidth: 1))
            .accessibilityHidden(true)
    }
}
