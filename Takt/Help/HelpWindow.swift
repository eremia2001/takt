import SwiftUI

// Hilfe-Fenster: links Suche und Themen, rechts der Inhalt des gewählten Themas.
// Rein darstellend (ohne Store/TaktCore), damit es im Render-Harness läuft; die Anbindung an
// Navigator, Einstellungen und Freigaben steckt in `HelpScene`.

/// Inhalt des Hilfe-Fensters.
struct HelpWindow: View {
    @Bindable var center: HelpCenter
    var context = HelpContext()
    /// Knopf „Dort hin“ und Links.
    var perform: (HelpDestination) -> Void = { _ in }
    /// Lebende Bausteine (Freigaben, Datenbank).
    var live: (HelpBlock.Live) -> AnyView = { _ in AnyView(EmptyView()) }

    @Environment(\.colorScheme) private var scheme
    @FocusState private var isSearchFocused: Bool

    private var theme: DesignTheme { DesignTheme(scheme: scheme) }

    static let minSize = CGSize(width: 720, height: 480)

    private var results: [HelpTopic] { HelpContent.search(center.searchText) }

    /// Gewähltes Thema; passt es nicht zur Suche, das erste Suchergebnis.
    private var topic: HelpTopic? {
        let results = results
        return results.first { $0.id == center.selectedTopicID } ?? results.first
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 236)
                .background(theme.track.opacity(0.55))
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.window)
        }
        .frame(minWidth: Self.minSize.width, minHeight: Self.minSize.height)
        .background(theme.window)
        .background { searchShortcut }
    }

    // MARK: Seitenleiste

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            searchField
                .padding(.horizontal, 12)
                .padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(results) { item in
                        topicRow(item)
                    }
                    if results.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nichts gefunden")
                                .font(.system(size: 12.5, weight: .medium))
                            Text("Andere Wörter versuchen, z. B. „Pause“, „Widget“ oder „CSV“.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Hilfe durchsuchen", text: $center.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearchFocused)
                .onSubmit {
                    if let first = results.first { center.selectedTopicID = first.id }
                }
            if !center.searchText.isEmpty {
                Button {
                    center.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Suche leeren")
                .accessibilityLabel("Suche leeren")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSearchFocused ? Color.accentColor.opacity(0.5) : theme.hairline, lineWidth: 1)
        )
    }

    private func topicRow(_ item: HelpTopic) -> some View {
        let isSelected = item.id == topic?.id
        return Button {
            center.selectedTopicID = item.id
        } label: {
            HStack(spacing: 9) {
                Image(systemName: item.icon)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .frame(width: 20)
                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(isSelected ? theme.surface : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// ⌘F setzt den Cursor ins Suchfeld.
    private var searchShortcut: some View {
        Button("Suchen") { isSearchFocused = true }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Inhalt

    @ViewBuilder
    private var detail: some View {
        if let topic {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(topic)
                        .padding(.bottom, 6)
                    ForEach(Array(topic.blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 26)
                .padding(.bottom, 36)
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(topic.id)
        } else {
            Text("Kein Thema gefunden")
                .foregroundStyle(.secondary)
        }
    }

    private func header(_ topic: HelpTopic) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: topic.icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(scheme == .dark ? 0.2 : 0.12),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(topic.title)
                    .font(.system(size: 22, weight: .bold))
                Text(context.resolve(topic.summary))
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if let destination = topic.destination {
                Button {
                    perform(destination)
                } label: {
                    Label("Dort hin", systemImage: "arrow.up.forward.app")
                }
                .controlSize(.large)
                .help("Öffnet \(destination.title)")
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: HelpBlock) -> some View {
        switch block {
        case .heading(let text):
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 8)
        case .paragraph(let text):
            markdown(text)
                .font(.system(size: 13))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        markdown(item)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.system(size: 13))
        case .steps(let title, let items):
            HelpStepsCard(title: title, steps: items.map { markdown($0) })
        case .shortcuts(let title, let items):
            HelpShortcutTable(title: title, shortcuts: items, context: context)
        case .examples(let items):
            HelpExampleTable(examples: items, context: context)
        case .tip(let text):
            callout(text, symbol: "lightbulb", tint: Color.yellow.mix(with: .orange, by: 0.35))
        case .note(let text):
            callout(text, symbol: "info.circle", tint: .accentColor)
        case .link(let title, let destination):
            Button {
                perform(destination)
            } label: {
                HStack(spacing: 4) {
                    Text(title)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .buttonStyle(.link)
            .font(.system(size: 13, weight: .medium))
            .help("Öffnet \(destination.title)")
        case .live(let kind):
            live(kind)
        }
    }

    private func callout(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            markdown(text)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.track, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func markdown(_ text: String) -> Text {
        HelpMarkdown.text(context.resolve(text))
    }
}

/// Einfaches Inline-Markdown (`**fett**`, `` `Code` ``) für Hilfe-Texte.
enum HelpMarkdown {
    static func text(_ source: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: source, options: options) {
            return Text(attributed)
        }
        return Text(source)
    }
}

// MARK: - Bausteine

/// Taste bzw. Kürzel als Kapsel, z. B. „⌘K“.
struct HelpKeyCap: View {
    let keys: String
    var size: CGFloat = 12

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = DesignTheme(scheme: scheme)
        Text(keys)
            .font(.system(size: size, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, size * 0.55)
            .frame(minWidth: size * 2, minHeight: size * 1.85)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: size * 0.5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.5, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.08), radius: 0, y: 1)
            .accessibilityLabel(keys)
    }
}

/// Karte „So geht's“ mit nummerierten Schritten.
struct HelpStepsCard: View {
    let title: String?
    let steps: [Text]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = DesignTheme(scheme: scheme)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "list.number")
                    .font(.system(size: 11, weight: .semibold))
                Text(title.map { "So geht’s: \($0)" } ?? "So geht’s")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.accentColor, in: Circle())
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4.5 }
                    step
                        .font(.system(size: 13))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
    }
}

/// Tabelle Kürzel → Wirkung.
struct HelpShortcutTable: View {
    let title: String?
    let shortcuts: [HelpShortcut]
    var context = HelpContext()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
                ForEach(shortcuts, id: \.self) { shortcut in
                    GridRow {
                        HelpKeyCap(keys: context.resolve(shortcut.keys))
                            // Gleiche Spaltenbreite in allen Tabellen, damit sie untereinander fluchten.
                            .frame(minWidth: 118, alignment: .trailing)
                            .gridColumnAlignment(.trailing)
                        Text(context.resolve(shortcut.text))
                            .font(.system(size: 13))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// Tabelle Eingabe → Ergebnis.
struct HelpExampleTable: View {
    let examples: [HelpExample]
    var context = HelpContext()

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = DesignTheme(scheme: scheme)
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
            ForEach(examples, id: \.self) { example in
                GridRow {
                    Text(example.input)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(theme.track, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text(context.resolve(example.result))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
