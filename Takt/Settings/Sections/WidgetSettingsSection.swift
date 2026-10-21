import SwiftUI
import TaktCore
import WidgetKit

/// Abschnitt „Widget“: Darstellungsstil und wie man das Widget hinzufügt.
struct WidgetSettingsSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Section {
            VStack(alignment: .leading, spacing: 6) {
                Picker("Stil", selection: $settings.widgetStyle) {
                    ForEach(WidgetStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .help("Gilt für alle Takt-Widgets; sie zeichnen sich sofort neu")
                Text(settings.widgetStyle.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Gilt für alle Widgets mit Stil „Standard“. Standard: Schlicht.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Aussehen")
        }
        // Widget sofort im neuen Stil zeichnen statt erst bei der nächsten Timeline.
        .onChange(of: settings.widgetStyle) { WidgetCenter.shared.reloadAllTimelines() }

        Section {
            VStack(alignment: .leading, spacing: 6) {
                step(1, "Rechtsklick auf den Schreibtisch › „Widgets bearbeiten …“")
                step(2, "„Takt“ suchen und Größe wählen (klein, mittel oder groß)")
                step(3, "Auf den Schreibtisch ziehen. Rechtsklick auf das Widget › „Widget bearbeiten …“ wählt je Widget einen eigenen Stil oder ein festes Projekt.")
            }
            .padding(.vertical, 2)
        } header: {
            Text("Widget hinzufügen")
        } footer: {
            Text("Das Widget zeigt, was läuft, und hat einen Start-/Stopp-Knopf. Ein Klick darauf öffnet Takt.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .background(.quaternary, in: Circle())
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
