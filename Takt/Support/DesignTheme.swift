import SwiftUI

// Bewusst ohne Store- und TaktCore-Abhängigkeit, damit die Ansichten auch außerhalb der App
// (Vorschauen, Render-Harness) gezeichnet werden können.

/// Fenster- und Flächentöne des Hauptfensters, hell/dunkel. Bewusst nur wenige Stufen.
struct DesignTheme {
    let scheme: ColorScheme
    var dark: Bool { scheme == .dark }

    /// Fenstergrund – leicht warm statt reinweiß, nimmt dem Fenster das „Formular“-Gefühl.
    var window: Color { dark ? Color(white: 0.105) : Color(red: 0.972, green: 0.970, blue: 0.962) }
    /// Ruhige Fläche (Karten).
    var surface: Color { dark ? Color(white: 0.155) : .white }
    var hairline: Color { dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07) }
    var track: Color { dark ? Color.white.opacity(0.07) : Color.black.opacity(0.055) }
    var tertiary: Color { dark ? Color.white.opacity(0.36) : Color.black.opacity(0.32) }

    /// Getönte Fläche in Projektfarbe (Kapseln).
    func tint(_ color: Color, strong: Bool = false) -> Color {
        color.opacity(dark ? (strong ? 0.30 : 0.20) : (strong ? 0.20 : 0.12))
    }

    /// Verlauf der Farbkarte, wie Widget „Farbfläche“. `base` ist die Projektfarbe hinter Weiß.
    func colorField(_ base: Color) -> some View {
        ZStack {
            LinearGradient(
                colors: dark
                    ? [base.mix(with: .black, by: 0.28), base.mix(with: .black, by: 0.52)]
                    : [base.mix(with: .white, by: 0.08), base.mix(with: .black, by: 0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [.white.opacity(dark ? 0.10 : 0.18), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 420
            )
        }
    }
}

/// Farbrechnungen auf `#RRGGBB`-Werten.
enum DesignColor {
    /// Relative Helligkeit (WCAG) einer Hex-Farbe; ungültige Werte gelten als dunkel.
    static func luminance(_ hex: String) -> Double {
        guard let (r, g, b) = rgb(hex) else { return 0.2 }
        func linear(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// Projektfarbe als Grund für weiße Schrift (helle Farben werden abgedunkelt) –
    /// gleiche Regel wie `colorBehindWhite` im Widget.
    static func behindWhite(_ hex: String) -> Color {
        let extra = max(0, (luminance(hex) - 0.22) * 0.9)
        return Color(hex: hex).mix(with: .black, by: extra)
    }

    private static func rgb(_ hex: String) -> (Double, Double, Double)? {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }
}

/// Stopp-Glyphe: abgerundetes Quadrat.
struct StopGlyph: View {
    var color: Color
    var size: CGFloat = 10

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Schmaler Knopf mit Haarlinien-Rand, z. B. „+ Eintrag“, „+ Projekt“.
struct OutlinePillButton: View {
    let title: String
    var systemImage = "plus"
    let theme: DesignTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .overlay(Capsule().stroke(theme.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
