import SwiftUI

// Bausteine für Tags: kleine Kapsel zur Anzeige und klickbare Vorschläge unter einem Tag-Feld.
// Ohne Store- und TaktCore-Abhängigkeit (Vorschauen, Render-Harness); die Vorschläge liefert
// der Aufrufer, in der App aus `TaktStore.tagSuggestions(projectId:prefix:)`.

/// Tag als kleine, leise Kapsel hinter einem Projektnamen oder vor einer Notiz.
struct TagCapsule: View {
    let tag: String

    var body: some View {
        Text(tag)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(.fill.quaternary, in: Capsule())
            .fixedSize()
            .accessibilityLabel("Tag \(tag)")
    }
}

/// Klickbare Tag-Vorschläge unter einem Tag-Feld. Blendet sich aus, wenn es keine gibt oder
/// der eingegebene Text schon genau einem Vorschlag entspricht.
struct TagSuggestionChips: View {
    @Binding var text: String
    /// Vorschläge zum aktuellen Text (Präfix), zuletzt genutzte zuerst.
    let suggestions: [String]
    var limit = 6

    /// Vorschläge ohne den bereits eingegebenen Tag.
    static func visible(_ suggestions: [String], text: String, limit: Int = 6) -> [String] {
        let current = normalized(text)
        if suggestions.contains(where: { normalized($0) == current }) { return [] }
        return Array(suggestions.prefix(limit))
    }

    var body: some View {
        let items = Self.visible(suggestions, text: text, limit: limit)
        if !items.isEmpty {
            FlowLayout(spacing: 4, lineSpacing: 4) {
                ForEach(items, id: \.self) { tag in
                    Button { text = tag } label: {
                        Text(tag)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(.fill.tertiary, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Tag „\(tag)“ übernehmen")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Tag-Vorschläge")
        }
    }

    /// Vergleich ohne `#`, Leerraum, Groß-/Kleinschreibung und Akzente.
    private static func normalized(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("#") { value.removeFirst() }
        return value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
