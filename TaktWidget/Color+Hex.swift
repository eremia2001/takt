import SwiftUI
import TaktCore

extension Color {
    /// Farbe aus `#RRGGBB` (Raute optional). Ungültige Werte ergeben Grau.
    init(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = .gray
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension Project {
    /// Projektfarbe – der einzige Farbakzent im Widget.
    var color: Color { Color(hex: colorHex) }
}

extension Project {
    /// Relative Luminanz (WCAG) der Projektfarbe, 0 … 1.
    var luminance: Double {
        var digits = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return 0.2 }
        func linear(_ channel: UInt32) -> Double {
            let x = Double(channel) / 255
            return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear((value >> 16) & 0xFF)
            + 0.7152 * linear((value >> 8) & 0xFF)
            + 0.0722 * linear(value & 0xFF)
    }

    /// Projektfarbe als Grund für weiße Schrift oder Glyphen: helle Farben (Grün, Teal, Orange)
    /// werden je nach Luminanz abgedunkelt, dunkle bleiben unverändert.
    var colorBehindWhite: Color {
        let extra = max(0, (luminance - 0.22) * 0.9)
        return color.mix(with: .black, by: extra)
    }
}
