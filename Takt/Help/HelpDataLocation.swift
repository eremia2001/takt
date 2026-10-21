import AppKit
import SwiftUI

/// Hilfe › Daten & Sicherung: Ort der Datenbank und vorhandene Sicherungen (`.bak-*`).
/// Bekommt den Pfad von außen (`AppDatabase.defaultURL()`), damit es ohne TaktCore rendert.
struct HelpDataLocation: View {
    let databaseURL: URL

    @Environment(\.colorScheme) private var scheme
    @State private var backups: [URL] = []

    var body: some View {
        let theme = DesignTheme(scheme: scheme)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "cylinder.split.1x2")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Datenbank")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(displayPath(databaseURL))
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Im Finder zeigen") {
                    NSWorkspace.shared.activateFileViewerSelecting([databaseURL])
                }
            }
            Divider()
            if backups.isEmpty {
                Text("Noch keine automatischen Sicherungen – sie entstehen beim ersten Update des Datenbankformats.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text(backups.count == 1 ? "1 Sicherung im selben Ordner:" : "\(backups.count) Sicherungen im selben Ordner:")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                FlowRow(items: backups.map(\.lastPathComponent))
            }
        }
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
        .onAppear(perform: loadBackups)
    }

    /// `~` statt des Benutzerordners – kürzer und ohne Namen.
    private func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    /// Hauptdateien der Sicherungen (`takt.sqlite.bak-v1` …, ohne `-wal`/`-shm`).
    private func loadBackups() {
        let folder = databaseURL.deletingLastPathComponent()
        let prefix = databaseURL.lastPathComponent + ".bak-"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        backups = names
            .filter { $0.hasPrefix(prefix) && !$0.hasSuffix("-wal") && !$0.hasSuffix("-shm") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { folder.appendingPathComponent($0) }
    }
}

/// Dateinamen als kleine Kapseln nebeneinander.
private struct FlowRow: View {
    let items: [String]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = DesignTheme(scheme: scheme)
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(theme.track, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
    }
}
