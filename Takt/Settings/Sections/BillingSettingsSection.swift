import SwiftUI
import TaktCore

/// Abschnitt „Abrechnung“: Standard-Stundensatz und Wochenziel (häufig), darunter Rundung und
/// Währung (selten). Jede Einstellung mit Einheit und einem Satz Erklärung.
struct BillingSettingsSection: View {
    @Environment(AppSettings.self) private var settings

    /// Eingaben; übernommen wird nur Gültiges, damit halbe Eingaben nichts überschreiben.
    @State private var currencyText = ""
    @State private var rateText = ""
    @State private var goalText = ""

    var body: some View {
        @Bindable var settings = settings

        Section {
            HourlyRateField(
                title: "Standard-Stundensatz",
                text: $rateText,
                currencyCode: settings.currencyCode,
                prompt: "keiner",
                hint: "Gilt für alle Projekte ohne eigenen Satz (im Projekt einstellbar). Leer = kein Umsatz für diese Projekte."
            )

            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Wochenziel") {
                    HStack(spacing: 6) {
                        TextField("Wochenziel", text: $goalText, prompt: Text("keins"))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("h pro Woche")
                            .foregroundStyle(.secondary)
                    }
                }
                .help("Abrechenbare Stunden, die du pro Woche erreichen willst")
                Text("Abrechenbare Stunden pro Woche. " + Self.goalHint(goalText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Satz und Ziel")
        }

        Section {
            VStack(alignment: .leading, spacing: 4) {
                Picker("Rundung", selection: $settings.rounding) {
                    ForEach(Rounding.allCases, id: \.self) { rounding in
                        Text(rounding.title).tag(rounding)
                    }
                }
                Text("Rundet jeden Eintrag einzeln auf, z. B. bei 15 Min: 7 Min → 15 Min. Wirkt auf „Abrechenbar“, Umsatz und Export – die erfasste Zeit bleibt unverändert. Standard: Keine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Währung") {
                    TextField("Währung", text: $currencyText, prompt: Text("EUR"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                }
                Text(AppSettings.validCurrencyCode(currencyText) == nil
                     ? "Bitte drei Buchstaben eingeben, z. B. EUR oder CHF."
                     : "Drei Buchstaben (ISO-Code) für Beträge in Berichten und Export. Standard: EUR.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Berechnung")
        } footer: {
            Text("Ob ein Projekt abrechenbar ist, legst du im Projekt fest (Schalter „Abrechenbar“). Privatprojekte sind es standardmäßig nicht.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            currencyText = settings.currencyCode
            rateText = HourlyRateField.text(for: settings.defaultHourlyRate)
            goalText = Self.goalText(settings.weeklyGoalHours)
        }
        .onChange(of: goalText) {
            switch Self.parseGoal(goalText) {
            case .empty: settings.weeklyGoalHours = nil
            case .valid(let hours): if settings.weeklyGoalHours != hours { settings.weeklyGoalHours = hours }
            case .invalid: break
            }
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

// MARK: - Wochenziel

extension BillingSettingsSection {
    enum GoalInput: Equatable {
        case empty
        case valid(Double)
        case invalid
    }

    /// Leer → kein Ziel; sonst Stunden über 0 bis 168, Komma oder Punkt („32“, „32,5“).
    static func parseGoal(_ text: String) -> GoalInput {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return .empty }
        guard let value = Money.parse(text),
              let hours = SharedSettings.validWeeklyGoalHours(NSDecimalNumber(decimal: value).doubleValue)
        else { return .invalid }
        return .valid(hours)
    }

    /// Anzeige eines gespeicherten Ziels: „32“, „32,5“.
    static func goalText(_ hours: Double?) -> String {
        guard let hours else { return "" }
        if hours == hours.rounded() { return String(Int(hours)) }
        return String(format: "%.2f", hours)
            .replacingOccurrences(of: ".", with: ",")
            .replacingOccurrences(of: #",?0+$"#, with: "", options: .regularExpression)
    }

    static func goalHint(_ text: String) -> String {
        switch parseGoal(text) {
        case .empty:
            "Leer = kein Ziel. Mit Ziel zeigt der Wochenbericht den Fortschritt."
        case .valid(let hours):
            "Passt sich freien Tagen an: bei 4 Arbeitstagen gelten \(goalText(hours * 4 / 5)) h."
        case .invalid:
            "Bitte Stunden zwischen 0 und 168 eingeben, z. B. 32 oder 32,5."
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
