import SwiftUI

/// Einmaliger, dezenter Hinweis unter dem Fensterkopf für bestehende Nutzer:
/// „Neu: Befehlspalette ⌘K, Schnelleingabe ⌘N, Hilfe ⌘?“ – mit „Hilfe öffnen“ und ×.
struct WhatsNewBanner: View {
    var openPalette: () -> Void = {}
    var openHelp: () -> Void = {}
    var dismiss: () -> Void = {}

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = DesignTheme(scheme: scheme)
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            HStack(spacing: 6) {
                Text("Neu:").fontWeight(.semibold)
                item("Befehlspalette", "⌘K")
                Text("·").foregroundStyle(.tertiary)
                item("Schnelleingabe", "⌘N")
                Text("·").foregroundStyle(.tertiary)
                item("Hilfe", "⌘?")
            }
            .font(.system(size: 12.5))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            Button("Ausprobieren", action: openPalette)
                .buttonStyle(.link)
                .font(.system(size: 12.5, weight: .medium))
            Button("Hilfe öffnen", action: openHelp)
                .buttonStyle(.link)
                .font(.system(size: 12.5, weight: .medium))
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.tertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Hinweis ausblenden – er erscheint nicht wieder")
            .accessibilityLabel("Hinweis ausblenden")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 34)
        .background(Color.accentColor.opacity(scheme == .dark ? 0.14 : 0.08),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    private func item(_ title: String, _ keys: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
            HelpKeyCap(keys: keys, size: 10.5)
        }
    }
}
