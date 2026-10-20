import SwiftUI
import TaktCore
import WidgetKit

/// Abschnitt „Widget“: Darstellungsstil.
struct WidgetSettingsSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Section("Widget") {
            VStack(alignment: .leading, spacing: 6) {
                Picker("Stil", selection: $settings.widgetStyle) {
                    ForEach(WidgetStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Text(settings.widgetStyle.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // Widget sofort im neuen Stil zeichnen statt erst bei der nächsten Timeline.
        .onChange(of: settings.widgetStyle) { WidgetCenter.shared.reloadAllTimelines() }
    }
}
