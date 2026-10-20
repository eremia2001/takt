import SwiftUI

// Schnelleingabe außerhalb von „Heute“: kompakt im Menüleisten-Popover, groß im schwebenden
// Fenster (Spotlight-artig). Gleiche Grammatik und Vorschau wie `TodayQuickEntry`; die View dort
// ist an `TodayActions` und ⌘N gebunden und hat nur eine Größe, deshalb eine eigene.
// Rein darstellend: Auswerten und Übernehmen kommen als `QuickEntryHandlers` herein.

/// Aktionen der Schnelleingabe; in der App liefert sie `QuickEntryEngine` (Store).
struct QuickEntryHandlers {
    /// Live-Vorschau; `nil` bei leerem Text.
    var preview: (String) -> QuickEntryPreview? = { _ in nil }
    var commit: (String) -> Result<QuickEntrySuccess, QuickEntryFailure> = { _ in
        .failure(QuickEntryFailure(message: ""))
    }
    /// Ersetzt im Text das mehrdeutige Projekt durch das gewählte; `nil`, wenn das nicht gelingt.
    var resolve: (_ text: String, _ project: TodayData.ProjectItem) -> String? = { _, _ in nil }
}

/// Bestätigung nach dem Übernehmen.
struct QuickEntrySuccess: Hashable {
    /// „Eingetragen: Kundenportal · 09:00–10:30“ bzw. „Gestartet: Website“.
    let message: String
    let colorHex: String?
    /// Timer-Start (sonst fertiger Eintrag).
    let isStart: Bool
}

struct QuickEntryField: View {
    enum Size { case compact, large }

    let size: Size
    let theme: DesignTheme
    let handlers: QuickEntryHandlers
    /// Nach erfolgreichem Übernehmen (das Feld ist dann leer).
    var onSuccess: (QuickEntrySuccess) -> Void = { _ in }
    /// Esc bei leerem Feld (Fenster schließen bzw. Fokus abgeben).
    var onCancel: () -> Void = {}
    /// Kompakt: Knopf „Schnelleingabe…“ (öffnet das schwebende Fenster); `nil` = ohne.
    var openPanel: (() -> Void)? = nil
    /// Anzeige des Kurzbefehls fürs schwebende Fenster, z. B. „⌃⌥⌘N“.
    var panelShortcut: String? = nil
    /// Beim Erscheinen sofort tippen können (schwebendes Fenster).
    var focusOnAppear = false

    @State private var text: String
    @State private var confirmation: String?
    @State private var confirmationID = 0
    @State private var failure: String?
    @FocusState private var isFocused: Bool

    init(size: Size, theme: DesignTheme, handlers: QuickEntryHandlers, initialText: String = "",
         onSuccess: @escaping (QuickEntrySuccess) -> Void = { _ in }, onCancel: @escaping () -> Void = {},
         openPanel: (() -> Void)? = nil, panelShortcut: String? = nil, focusOnAppear: Bool = false) {
        self.size = size
        self.theme = theme
        self.handlers = handlers
        self.onSuccess = onSuccess
        self.onCancel = onCancel
        self.openPanel = openPanel
        self.panelShortcut = panelShortcut
        self.focusOnAppear = focusOnAppear
        _text = State(initialValue: initialText)
    }

    private var isLarge: Bool { size == .large }
    private var detailFont: Font { .system(size: isLarge ? 13 : 11.5, weight: .medium) }

    private var preview: QuickEntryPreview? {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : handlers.preview(text)
    }

    var body: some View {
        let preview = preview
        VStack(alignment: .leading, spacing: isLarge ? 0 : 6) {
            field(preview)
            if isLarge {
                Rectangle().fill(theme.hairline).frame(height: 1)
                statusLine(preview)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
            } else if failure != nil || preview != nil || confirmation != nil {
                statusLine(preview)
                    .padding(.leading, 10)
                    .padding(.trailing, 4)
            }
        }
        .onChange(of: text) { failure = nil }
        .onAppear {
            guard focusOnAppear else { return }
            // Erst im nächsten Durchlauf: Das Fenster muss schon Key sein.
            DispatchQueue.main.async { isFocused = true }
        }
    }

    // MARK: Feld

    private func field(_ preview: QuickEntryPreview?) -> some View {
        HStack(spacing: isLarge ? 12 : 7) {
            Image(systemName: "pencil.line")
                .font(.system(size: isLarge ? 19 : 11, weight: isLarge ? .regular : .semibold))
                .foregroundStyle(isLarge ? AnyShapeStyle(.secondary) : AnyShapeStyle(theme.tertiary))
            TextField(
                "Schnelleingabe",
                text: $text,
                prompt: Text(isLarge ? "Projekt, Zeit, #Tag, Notiz" : "Schnelleingabe · z. B. Website 1h30")
                    .foregroundStyle(theme.tertiary)
            )
            .textFieldStyle(.plain)
            .font(.system(size: isLarge ? 22 : 12.5, weight: isLarge ? .light : .regular))
            .focused($isFocused)
            .onSubmit(commit)
            .onExitCommand {
                if text.isEmpty && failure == nil {
                    isFocused = false
                    onCancel()
                } else {
                    clear()
                }
            }
            trailing(preview)
        }
        .padding(.leading, isLarge ? 18 : 10)
        .padding(.trailing, isLarge ? 16 : 4)
        .frame(height: isLarge ? 56 : 28)
        .background {
            if !isLarge {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.surface)
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isFocused ? Color.accentColor.opacity(0.55) : theme.hairline, lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }

    @ViewBuilder
    private func trailing(_ preview: QuickEntryPreview?) -> some View {
        if preview?.isValid == true {
            Image(systemName: "return")
                .font(.system(size: isLarge ? 13 : 10.5, weight: .semibold))
                .foregroundStyle(theme.tertiary)
                .help("Mit Enter übernehmen")
                .padding(.trailing, isLarge ? 0 : 4)
        } else if isLarge, let panelShortcut {
            KeyCap(text: panelShortcut, theme: theme)
        } else if let openPanel {
            OpenPanelButton(theme: theme, shortcut: panelShortcut, action: openPanel)
        }
    }

    // MARK: Statuszeile

    @ViewBuilder
    private func statusLine(_ preview: QuickEntryPreview?) -> some View {
        if let failure {
            messageLine(failure, emphasized: true)
        } else if let preview {
            previewLine(preview)
        } else if let confirmation {
            confirmationLine(confirmation)
        } else if isLarge {
            hintLine
        }
    }

    @ViewBuilder
    private func previewLine(_ preview: QuickEntryPreview) -> some View {
        switch preview {
        case let .entry(project, day, start, end, tag, note):
            let parts = [day, "\(TodayFormat.clock(start))–\(TodayFormat.clock(end))",
                         TodayFormat.duration(end.timeIntervalSince(start)), tag.map { "#\($0)" }, note]
            projectLine(project: project, lead: nil, details: parts.compactMap { $0 }, hint: "eintragen")
        case let .start(project, since, tag, note):
            let lead = since.map { "Startet ab \(TodayFormat.clock($0)):" } ?? "Startet jetzt:"
            projectLine(project: project, lead: lead,
                        details: [tag.map { "#\($0)" }, note].compactMap { $0 }, hint: "starten")
        case let .ambiguous(message, candidates):
            HStack(spacing: 6) {
                warningIcon
                if isLarge {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                ForEach(candidates.prefix(isLarge ? 5 : 3)) { project in
                    Button { resolve(project) } label: {
                        HStack(spacing: 5) {
                            Circle().fill(project.color).frame(width: 6, height: 6)
                            Text(project.name)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, isLarge ? 10 : 7)
                        .frame(height: isLarge ? 24 : 19)
                        .background(theme.tint(project.color, strong: true), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("„\(project.name)“ wählen")
                }
                Spacer(minLength: 0)
            }
            .font(detailFont)
            .frame(height: isLarge ? 24 : 19)
        case let .error(message):
            messageLine(message, emphasized: false)
        }
    }

    private func projectLine(project: TodayData.ProjectItem, lead: String?, details: [String], hint: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(project.color).frame(width: 7, height: 7)
            if let lead {
                Text(lead).foregroundStyle(.secondary).fixedSize()
            }
            Text(project.name)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(1)
            ForEach(Array(details.enumerated()), id: \.offset) { _, part in
                Text("·").foregroundStyle(theme.tertiary)
                Text(part)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if isLarge {
                Text("↩ \(hint)")
                    .foregroundStyle(theme.tertiary)
                    .fixedSize()
            }
        }
        .font(detailFont)
        .monospacedDigit()
        .frame(height: 19)
    }

    private func messageLine(_ text: String, emphasized: Bool) -> some View {
        HStack(spacing: 6) {
            warningIcon
            Text(text)
                .foregroundStyle(emphasized ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(detailFont)
        .frame(height: 19)
    }

    private func confirmationLine(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(detailFont)
        .monospacedDigit()
        .frame(height: 19)
        .transition(.opacity)
    }

    /// Großes Fenster, leeres Feld: kurze Grammatik-Hilfe.
    private var hintLine: some View {
        HStack(spacing: 6) {
            Text("z. B.")
                .foregroundStyle(theme.tertiary)
            Text("kunden 9-10:30 #meeting")
                .foregroundStyle(.secondary)
            Text("·").foregroundStyle(theme.tertiary)
            Text("Website 1h30")
                .foregroundStyle(.secondary)
            Text("·").foregroundStyle(theme.tertiary)
            Text("Garten seit 9:30")
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text("esc schließen")
                .foregroundStyle(theme.tertiary)
                .fixedSize()
        }
        .font(detailFont)
        .lineLimit(1)
        .frame(height: 19)
    }

    private var warningIcon: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: isLarge ? 12.5 : 10.5, weight: .semibold))
            .foregroundStyle(.orange)
    }

    // MARK: Aktionen

    private func commit() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        switch handlers.commit(text) {
        case .success(let success):
            text = ""
            failure = nil
            if !isLarge { showConfirmation(success.message) }
            onSuccess(success)
        case .failure(let error):
            failure = error.message
        }
    }

    private func clear() {
        text = ""
        failure = nil
    }

    private func resolve(_ project: TodayData.ProjectItem) {
        if let resolved = handlers.resolve(text, project) {
            text = resolved
        }
        isFocused = true
    }

    private func showConfirmation(_ message: String) {
        confirmationID += 1
        let id = confirmationID
        withAnimation(.easeOut(duration: 0.15)) { confirmation = message }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard confirmationID == id else { return }
            withAnimation(.easeIn(duration: 0.3)) { confirmation = nil }
        }
    }
}

// MARK: - Bausteine

/// Tastenkappe mit Haarlinie, z. B. „⌃⌥⌘N“.
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

/// Knopf „Schnelleingabe…“ im Popover-Feld: öffnet das schwebende Fenster.
private struct OpenPanelButton: View {
    let theme: DesignTheme
    let shortcut: String?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(theme.tertiary))
                .frame(width: 22, height: 20)
                .background(isHovered ? theme.track : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(shortcut.map { "Schnelleingabe… (\($0))" } ?? "Schnelleingabe…")
        .accessibilityLabel("Schnelleingabe…")
    }
}
