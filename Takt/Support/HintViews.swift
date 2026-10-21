import SwiftUI

// Bausteine für Erklärungen: Kontext-Tipp, Freigabe-Statuszeile, Einleitung eines
// Einstellungsreiters und leere Zustände im Hauptfenster.
// Ohne Store- und TaktCore-Abhängigkeit (wie `DesignTheme`), damit sie im Render-Harness laufen.

// MARK: - Kontext-Tipp

/// Dezente, einmalige Tipp-Zeile: Glühbirne, Text, optional ein Link, ×. Verschwindet dauerhaft,
/// sobald sie geschlossen wird (`TipStore`).
struct TipRow: View {
    let tip: TipID
    /// Optionaler Link hinter dem Text, z. B. „Öffnen“.
    var actionTitle: String?
    var action: (() -> Void)?
    var compact = false

    @Environment(\.colorScheme) private var scheme
    private var theme: DesignTheme { DesignTheme(scheme: scheme) }
    private var tips: TipStore { TipStore.shared }

    var body: some View {
        if tips.isVisible(tip) {
            HStack(alignment: .center, spacing: compact ? 6 : 8) {
                Image(systemName: "lightbulb")
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(Color.yellow.mix(with: .orange, by: 0.35))
                    .accessibilityHidden(true)
                Text(tip.text)
                    .font(.system(size: compact ? 11 : 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 2 : 1)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.link)
                        .font(.system(size: compact ? 11 : 12, weight: .medium))
                        .fixedSize()
                }
                Spacer(minLength: 4)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { tips.dismiss(tip) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.tertiary)
                        .frame(width: 18, height: 18)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Tipp ausblenden – er erscheint nicht wieder")
                .accessibilityLabel("Tipp ausblenden")
            }
            .padding(.leading, compact ? 8 : 10)
            .padding(.trailing, 4)
            .frame(minHeight: compact ? 24 : 26)
            .background(theme.track.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .transition(.opacity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tipp: \(tip.text)")
        }
    }
}

// MARK: - Freigaben

/// Zustand einer Systemfreigabe für `PermissionRow`.
enum PermissionState: Equatable {
    /// Erteilt – grün.
    case granted(String = "Erlaubt")
    /// Erteilt, aber eingeschränkt (z. B. Mitteilungen ohne Banner) – orange.
    case limited(String)
    /// Noch nicht gefragt – orange.
    case notDetermined(String = "Noch nicht erlaubt")
    /// Abgelehnt – rot.
    case denied(String = "Abgelehnt")
    /// Status wird gelesen.
    case checking

    var label: String {
        switch self {
        case .granted(let text), .limited(let text), .notDetermined(let text), .denied(let text): text
        case .checking: "Wird geprüft …"
        }
    }

    var color: Color {
        switch self {
        case .granted: .green
        case .limited, .notDetermined: .orange
        case .denied: .red
        case .checking: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .granted: "checkmark.circle.fill"
        case .limited, .notDetermined: "exclamationmark.circle.fill"
        case .denied: "xmark.circle.fill"
        case .checking: "circle.dotted"
        }
    }
}

/// Einheitliche Statuszeile für eine Systemfreigabe: Symbol, Name, farbiger Status, Knopf
/// („Erlauben“ bzw. „Systemeinstellungen…“) und ein Satz, wofür Takt sie braucht.
struct PermissionRow: View {
    let symbol: String
    let title: String
    let state: PermissionState
    /// Wofür die Freigabe nötig ist – ein Satz.
    let purpose: String
    /// Systemabfrage auslösen; nur bei `.notDetermined` als „Erlauben“ gezeigt.
    var request: (() -> Void)?
    /// Systemeinstellungen an der passenden Stelle öffnen.
    var openSettings: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.gray.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                    Label {
                        Text(state.label)
                    } icon: {
                        Image(systemName: state.symbol)
                            .foregroundStyle(state.color)
                    }
                    .font(.callout)
                    .foregroundStyle(state == .checking ? AnyShapeStyle(.secondary) : AnyShapeStyle(state.color))
                    .lineLimit(1)
                }
                Text(purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            button
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title): \(state.label)")
    }

    @ViewBuilder
    private var button: some View {
        switch state {
        case .notDetermined:
            if let request {
                Button("Erlauben", action: request)
                    .buttonStyle(.borderedProminent)
                    .help("Zeigt die Abfrage von macOS")
            } else if let openSettings {
                Button("Systemeinstellungen…", action: openSettings)
                    .help("Öffnet die passende Stelle in den Systemeinstellungen")
            }
        case .denied, .limited:
            if let openSettings {
                Button("Systemeinstellungen…", action: openSettings)
                    .buttonStyle(.borderedProminent)
                    .help("Öffnet die passende Stelle in den Systemeinstellungen")
            }
        case .granted:
            if let openSettings {
                Button("Systemeinstellungen…", action: openSettings)
                    .buttonStyle(.link)
                    .font(.callout)
                    .help("Öffnet die passende Stelle in den Systemeinstellungen")
            }
        case .checking:
            ProgressView().controlSize(.small)
        }
    }
}

// MARK: - Einstellungen

/// Erste Zeile eines Einstellungsreiters: Symbol und ein Satz „Hier stellst du ein, …“.
struct SettingsIntro: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

/// Hinweis unter einem Steuerelement: „Standard: 75 Min“ o. Ä. (klein, sekundär).
struct SettingHint: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Leerer Zustand

/// Leerer Zustand im Hauptfenster: Symbol, Titel, Erklärung, optional Schritte, Knopf und Hilfe.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var steps: [String] = []
    var actionTitle: String?
    var action: (() -> Void)?
    var helpTopic: String?

    @Environment(\.colorScheme) private var scheme
    private var theme: DesignTheme { DesignTheme(scheme: scheme) }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.tertiary)
                .frame(width: 48, height: 48)
                .background(theme.track, in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)
            if !steps.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(width: 18, height: 18)
                                .background(theme.track, in: Circle())
                            Text(step)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: 420, alignment: .leading)
                .padding(.top, 4)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .background(Color.accentColor, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            if let helpTopic {
                HelpLink(topic: helpTopic)
                    .padding(.top, actionTitle == nil ? 4 : 0)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
