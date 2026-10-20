import SwiftUI

// Schnelleingabe in „Heute“: ein ruhiges Feld unter den Start-Kapseln, Fokus per ⌘N.
// Beim Tippen zeigt eine Zeile darunter, was übernommen würde („Kundenportal · 09:00–10:30 ·
// 1:30 · #meeting · Standup“) bzw. warum nicht. Enter übernimmt, Esc leert.
// Rein darstellend: Auswerten und Übernehmen erledigen `TodayActions` (in der App der Store).

struct TodayQuickEntry: View {
    let theme: DesignTheme
    let actions: TodayActions

    @State private var text: String
    /// Kurze Bestätigung nach dem Übernehmen.
    @State private var confirmation: String?
    @State private var confirmationID = 0
    /// Fehler beim Übernehmen (Enter); verschwindet beim Weitertippen.
    @State private var failure: String?
    @FocusState private var isFocused: Bool

    init(theme: DesignTheme, actions: TodayActions, initialText: String = "") {
        self.theme = theme
        self.actions = actions
        _text = State(initialValue: initialText)
    }

    private var preview: QuickEntryPreview? {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : actions.previewQuickEntry(text)
    }

    var body: some View {
        let preview = preview
        VStack(alignment: .leading, spacing: 7) {
            field(preview)
            if let failure {
                messageLine(failure, emphasized: true)
            } else if let preview {
                previewLine(preview)
            } else if let confirmation {
                confirmationLine(confirmation)
            }
        }
        .onChange(of: text) { failure = nil }
    }

    // MARK: Feld

    private func field(_ preview: QuickEntryPreview?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil.line")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.tertiary)
            TextField(
                "Schnelleingabe",
                text: $text,
                prompt: Text("Schnelleingabe · z. B. Kundenportal 9:00-10:30 Review").foregroundStyle(theme.tertiary)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused($isFocused)
            .onSubmit(commit)
            .onExitCommand {
                // Esc: erst leeren, beim zweiten Mal den Fokus abgeben.
                if text.isEmpty && failure == nil { isFocused = false } else { clear() }
            }
            if text.isEmpty {
                Text("⌘N")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.tertiary)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(theme.hairline, lineWidth: 1))
                    .accessibilityHidden(true)
            } else if preview?.isValid == true {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.tertiary)
                    .help("Mit Enter übernehmen")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 30)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isFocused ? Color.accentColor.opacity(0.55) : theme.hairline, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .background {
            // ⌘N setzt den Fokus ins Feld (unsichtbarer Knopf, damit der Kurzbefehl immer gilt).
            Button("Schnelleingabe") { isFocused = true }
                .keyboardShortcut("n", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: Vorschau

    @ViewBuilder
    private func previewLine(_ preview: QuickEntryPreview) -> some View {
        switch preview {
        case let .entry(project, day, start, end, tag, note):
            let parts = [day, "\(TodayFormat.clock(start))–\(TodayFormat.clock(end))",
                         TodayFormat.duration(end.timeIntervalSince(start)), tag.map { "#\($0)" }, note]
            projectLine(project: project, lead: nil, details: parts.compactMap { $0 }, hint: "eintragen")
        case let .start(project, since, tag, note):
            let lead = since.map { "Startet ab \(TodayFormat.clock($0)):" } ?? "Startet jetzt:"
            projectLine(project: project, lead: lead, details: [tag.map { "#\($0)" }, note].compactMap { $0 }, hint: "starten")
        case let .ambiguous(message, candidates):
            HStack(spacing: 6) {
                warningIcon
                Text(message)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
                ForEach(candidates) { project in
                    Button { resolve(project) } label: {
                        HStack(spacing: 5) {
                            Circle().fill(project.color).frame(width: 6, height: 6)
                            Text(project.name)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(theme.tint(project.color), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("„\(project.name)“ wählen")
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 12, weight: .medium))
            .frame(height: 20)
            .padding(.leading, 12)
        case let .error(message):
            messageLine(message, emphasized: false)
        }
    }

    private func projectLine(project: TodayData.ProjectItem, lead: String?, details: [String], hint: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(project.color).frame(width: 7, height: 7)
            if let lead {
                Text(lead).foregroundStyle(.secondary)
            }
            Text(project.name)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
            ForEach(Array(details.enumerated()), id: \.offset) { _, part in
                Text("·").foregroundStyle(theme.tertiary)
                Text(part)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("↩ \(hint)")
                .foregroundStyle(theme.tertiary)
                .fixedSize()
        }
        .font(.system(size: 12, weight: .medium))
        .monospacedDigit()
        .frame(height: 20)
        .padding(.leading, 12)
        .padding(.trailing, 8)
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
        .font(.system(size: 12, weight: .medium))
        .frame(height: 20)
        .padding(.leading, 12)
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
        .font(.system(size: 12, weight: .medium))
        .monospacedDigit()
        .frame(height: 20)
        .padding(.leading, 12)
        .transition(.opacity)
    }

    private var warningIcon: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.orange)
    }

    // MARK: Aktionen

    private func commit() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        switch actions.commitQuickEntry(text) {
        case .success(let message):
            text = ""
            failure = nil
            showConfirmation(message)
        case .failure(let error):
            failure = error.message
        }
    }

    private func clear() {
        text = ""
        failure = nil
    }

    private func resolve(_ project: TodayData.ProjectItem) {
        if let resolved = actions.resolveQuickEntry(text, project) {
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
