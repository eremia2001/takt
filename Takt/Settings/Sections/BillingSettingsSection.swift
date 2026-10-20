import SwiftUI
import TaktCore

/// Abschnitt „Abrechnung“: Rundung, Währung, Standard-Stundensatz.
struct BillingSettingsSection: View {
    @Environment(AppSettings.self) private var settings

    /// Eingaben; übernommen wird nur Gültiges, damit halbe Eingaben nichts überschreiben.
    @State private var currencyText = ""
    @State private var rateText = ""

    var body: some View {
        @Bindable var settings = settings

        Section("Abrechnung") {
            VStack(alignment: .leading, spacing: 4) {
                Picker("Rundung", selection: $settings.rounding) {
                    ForEach(Rounding.allCases, id: \.self) { rounding in
                        Text(rounding.title).tag(rounding)
                    }
                }
                Text("Aufgerundet wird jeder Eintrag einzeln, in Berichten und im Export.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Währung") {
                    TextField("Währung", text: $currencyText, prompt: Text("EUR"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                }
                if AppSettings.validCurrencyCode(currencyText) == nil {
                    Text("Drei Buchstaben, z. B. EUR oder CHF.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HourlyRateField(
                title: "Standard-Stundensatz",
                text: $rateText,
                currencyCode: settings.currencyCode,
                prompt: "keiner",
                hint: "Gilt für Projekte ohne eigenen Satz."
            )
        }
        .onAppear {
            currencyText = settings.currencyCode
            rateText = HourlyRateField.text(for: settings.defaultHourlyRate)
        }
        .onChange(of: currencyText) {
            // Auf drei Großbuchstaben begrenzen; nur Gültiges speichern.
            let filtered = String(currencyText.uppercased().filter { $0.isASCII && $0.isLetter }.prefix(3))
            if filtered != currencyText {
                currencyText = filtered
                return
            }
            if let code = AppSettings.validCurrencyCode(filtered), code != settings.currencyCode {
                settings.currencyCode = code
            }
        }
        .onChange(of: rateText) {
            switch HourlyRateField.parse(rateText) {
            case .empty: settings.defaultHourlyRate = nil
            case .valid(let rate): settings.defaultHourlyRate = rate
            case .invalid: break
            }
        }
    }
}

/// Eingabefeld für einen Stundensatz mit Währung, z. B. „85,00 EUR/h“.
/// Reine Darstellung; das Auswerten übernimmt der Aufrufer per `HourlyRateField.parse`.
struct HourlyRateField: View {
    let title: String
    @Binding var text: String
    let currencyCode: String
    /// Platzhalter bei leerem Feld, z. B. „keiner“ oder der Standard-Stundensatz.
    var prompt: String = ""
    /// Erklärung unter dem Feld, wenn die Eingabe gültig ist.
    var hint: String?

    enum Result: Equatable {
        case empty
        case valid(Decimal)
        case invalid
    }

    /// Leer → `.empty`; Zahl ≥ 0 in deutscher oder englischer Schreibweise → `.valid`.
    static func parse(_ text: String) -> Result {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return .empty }
        guard let value = Money.parse(text), value >= 0 else { return .invalid }
        return .valid(value)
    }

    /// Anzeige eines gespeicherten Satzes: „85“, „92,50“.
    static func text(for rate: Decimal?) -> String {
        guard let rate else { return "" }
        let full = Money.germanString(rate)
        return full.hasSuffix(",00") ? String(full.dropLast(3)) : full
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                HStack(spacing: 6) {
                    TextField(title, text: $text, prompt: Text(prompt))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    Text("\(currencyCode)/h")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if Self.parse(text) == .invalid {
                Text("Bitte eine Zahl eingeben, z. B. 85 oder 92,50.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
