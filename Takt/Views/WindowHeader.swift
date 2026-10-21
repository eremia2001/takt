import SwiftUI

/// Bereiche des Hauptfensters, umgeschaltet über die Tabs im Fensterkopf.
enum AppSection: String, CaseIterable, Identifiable {
    case today, reports, projects

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Heute"
        case .reports: "Berichte"
        case .projects: "Projekte"
        }
    }

    /// Tastenkürzel ⌘1 … ⌘3.
    var shortcut: KeyEquivalent {
        switch self {
        case .today: "1"
        case .reports: "2"
        case .projects: "3"
        }
    }
}

/// Fensterkopf: Titel links neben den Ampeln; rechts Tabs, „⌘K Befehle“, Hilfe „?“ und Zahnrad.
/// Liegt im (unsichtbaren) Titelleistenbereich; leere Flächen ziehen das Fenster.
/// Jedes Element hat einen Tooltip mit seinem Kürzel, damit sich die Kürzel einprägen.
struct WindowHeader: View {
    let title: String
    let selection: AppSection
    let theme: DesignTheme
    var select: (AppSection) -> Void = { _ in }
    var openSettings: () -> Void = {}
    var openPalette: () -> Void = {}
    var openHelp: () -> Void = {}

    /// Platz links für die Ampeln des Fensters.
    static let trafficLightInset: CGFloat = 84

    /// Mitte der Ampeln, vom oberen Fensterrand gemessen. Ohne Symbolleiste ist die
    /// (unsichtbare) Titelleiste ab macOS 26 32 pt hoch, davor 28 pt.
    static var trafficLightCenterY: CGFloat {
        if #available(macOS 26, *) { 16 } else { 14 }
    }

    /// Kopfhöhe: Zeile mittig zu den Ampeln, darunter Luft bis zum Inhalt.
    static var height: CGFloat { trafficLightCenterY + 26 }
    private static let rowHeight: CGFloat = 30

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.leading, Self.trafficLightInset)
            Spacer(minLength: 12)
            HStack(spacing: 2) {
                ForEach(AppSection.allCases) { section in
                    tab(section)
                }
            }
            paletteButton
                .padding(.leading, 14)
            iconButton("questionmark.circle", help: "Hilfe (⌘?)", label: "Hilfe", action: openHelp)
                .padding(.leading, 6)
            iconButton("gearshape", help: "Einstellungen (⌘,)", label: "Einstellungen", action: openSettings)
        }
        .padding(.trailing, 20)
        .frame(height: Self.rowHeight)
        .padding(.top, Self.trafficLightCenterY - Self.rowHeight / 2)
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .top)
        .background {
            // Leere Kopffläche verhält sich wie eine Titelleiste.
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
    }

    private func tab(_ section: AppSection) -> some View {
        let isSelected = section == selection
        return Button {
            select(section)
        } label: {
            Text(section.title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(isSelected ? theme.track : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(section.shortcut, modifiers: .command)
        .help("\(section.title) (⌘\(String(section.shortcut.character)))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Dezente Kapsel „⌘K Befehle“ (wie ein Tab) – öffnet die Befehlspalette.
    private var paletteButton: some View {
        Button(action: openPalette) {
            HStack(spacing: 6) {
                HStack(spacing: 1) {
                    Image(systemName: "command")
                        .font(.system(size: 10, weight: .semibold))
                    Text("K")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(theme.tertiary)
                Text("Befehle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11)
            .frame(height: 26)
            // Leiser als der gewählte Tab, damit es nicht wie ein vierter Bereich wirkt.
            .background(theme.track.opacity(0.5), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Befehlspalette (⌘K): alles per Tastatur – Projekte starten, Berichte, Einstellungen, Hilfe")
        .accessibilityLabel("Befehlspalette öffnen")
    }

    private func iconButton(_ symbol: String, help: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
    }
}
