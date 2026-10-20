import AppKit
import SwiftUI
#if canImport(TaktCore)
import TaktCore
#endif

// Anzeige in der Menüleiste als fertiges Bild. Die Menüleiste zeichnet SwiftUI-Formen nur
// einfarbig; deshalb wird das ganze Label (Farbpunkt, Kapsel, Ring, Text) per `ImageRenderer`
// in ein `NSImage` gerendert (Höhe 22 pt, Scale 2) und minütlich bzw. bei Zustandswechsel neu
// erzeugt. Rein darstellend und ohne Store, damit Einstellungen (Live-Vorschau) und das
// Render-Harness dasselbe Bild bekommen.
//
// Template oder nicht: Ohne laufenden Timer ist alles einfarbig → Template-Bild, macOS färbt es
// passend zur Menüleiste (auch hervorgehoben). Läuft ein Timer, gibt es Projektfarben → kein
// Template, Text und Glyphe werden selbst nach der Helligkeit der Menüleiste gefärbt.

/// Darstellungsstil der Menüleiste (Einstellung `menuBarStyle`).
enum MenuBarStyle: String, CaseIterable, Identifiable {
    /// Ring-Glyphe wie im App-Symbol; läuft ein Timer, ist ihr Punkt in Projektfarbe.
    case icon
    /// Farbpunkt + `h:mm`.
    case compact
    /// Farbpunkt + „Projekt · h:mm“ (bisheriges Verhalten).
    case text
    /// Pille in Projektfarbe mit weißem Text.
    case capsule
    /// 16-pt-Ring in Projektfarbe + `h:mm`.
    case ring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icon: "Symbol"
        case .compact: "Kompakt"
        case .text: "Text"
        case .capsule: "Kapsel"
        case .ring: "Ring"
        }
    }
}

/// Darstellung, wenn kein Timer läuft (Einstellung `menuBarIdleMode`).
enum MenuBarIdleMode: String, CaseIterable, Identifiable {
    /// Nur die Ring-Glyphe.
    case symbol
    /// Glyphe bzw. graue Kapsel mit der Tagessumme.
    case symbolAndTotal
    /// Gar nicht anzeigen – das Menüleistenobjekt erscheint nur bei laufendem Timer
    /// (bzw. in einer Pomodoro-Pause).
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .symbol: "Nur Symbol"
        case .symbolAndTotal: "Symbol und Tagessumme"
        case .hidden: "Ausblenden"
        }
    }
}

/// Alles, was das Label zeigt – ohne Store-Abhängigkeit.
struct MenuBarLabelModel: Equatable {
    struct Running: Equatable {
        var name: String
        var colorHex: String
        /// Laufzeit des aktuellen Eintrags.
        var elapsed: TimeInterval
        /// Budgetverbrauch des Projekts (1 = 100 %); `nil` ohne Budget.
        var budgetFraction: Double?
    }

    struct Pomodoro: Equatable {
        var isBreak: Bool
        /// Restzeit wie bisher, z. B. „23:00“.
        var clock: String
        /// Fortschritt der Phase 0…1 (für den Ring).
        var progress: Double
    }

    var style: MenuBarStyle = .text
    var showProjectName = true
    /// Tagessumme statt Laufzeit des Eintrags.
    var showTodayTotal = false
    var idleMode: MenuBarIdleMode = .symbol
    var running: Running?
    /// Tagessumme inklusive laufendem Eintrag.
    var todayTotal: TimeInterval = 0
    var pomodoro: Pomodoro?
    /// Helligkeit der Menüleiste (nur für farbige, nicht-Template-Bilder).
    var isDark = false

    /// Ohne laufenden Timer ist das Bild einfarbig und wird als Template gezeichnet.
    var isTemplate: Bool { running == nil }

    /// Ob das Menüleistenobjekt überhaupt erscheinen soll (`hidden` in der Pause).
    var isVisible: Bool { running != nil || pomodoro != nil || idleMode != .hidden }

    /// Längere Namen kürzen, damit die Menüleiste nicht vollläuft.
    static let maxNameLength = 22

    static func shortened(_ name: String) -> String {
        name.count > maxNameLength ? String(name.prefix(maxNameLength - 1)) + "…" : name
    }

    /// Die angezeigte Zeit: Laufzeit oder (Einstellung) Tagessumme.
    var runningTime: String {
        guard let running else { return DurationFormat.hourMinute(todayTotal) }
        return DurationFormat.hourMinute(showTodayTotal ? todayTotal : running.elapsed)
    }

    /// „🍅 23:00“ bzw. „Pause 07:00“.
    var pomodoroText: String? {
        pomodoro.map { $0.isBreak ? "Pause \($0.clock)" : "🍅 \($0.clock)" }
    }

    var isOverBudget: Bool { (running?.budgetFraction ?? 0) > 1 }

    /// Text für VoiceOver.
    var accessibilityText: String {
        var parts: [String] = []
        if let running {
            parts.append("\(running.name) läuft seit \(DurationFormat.hourMinute(running.elapsed))")
            if showTodayTotal { parts.append("heute \(DurationFormat.hourMinute(todayTotal))") }
            if isOverBudget { parts.append("Budget überschritten") }
        } else {
            parts.append("Takt – nichts läuft")
            if idleMode == .symbolAndTotal { parts.append("heute \(DurationFormat.hourMinute(todayTotal))") }
        }
        if let pomodoroText { parts.append(pomodoroText) }
        return parts.joined(separator: ", ")
    }
}

enum MenuBarLabelRenderer {
    static let height: CGFloat = 22
    static let scale: CGFloat = 2

    /// Rendert das Label als Bild (22 pt hoch, Breite nach Inhalt).
    @MainActor
    static func image(for model: MenuBarLabelModel) -> NSImage {
        let renderer = ImageRenderer(content: MenuBarLabelView(model: model))
        renderer.scale = scale
        // Eigene Farbwahl statt Umgebungs-Schema: `.primary` hätte im Renderer kein Menüleisten-Erscheinungsbild.
        renderer.isOpaque = false
        guard let cgImage = renderer.cgImage else {
            return NSImage(size: NSSize(width: 18, height: height))
        }
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
        )
        image.isTemplate = model.isTemplate
        image.accessibilityDescription = model.accessibilityText
        return image
    }
}

// MARK: - Ansicht

/// Das gezeichnete Label. Für Template-Bilder (Pause) wird schwarz gezeichnet; macOS färbt um.
struct MenuBarLabelView: View {
    let model: MenuBarLabelModel

    private static let font = Font.system(size: 13, weight: .regular).monospacedDigit()
    private static let pillFont = Font.system(size: 12.5, weight: .semibold).monospacedDigit()

    /// Text-/Glyphenfarbe: Template → Schwarz (macOS färbt), sonst nach Menüleiste.
    private var ink: Color {
        if model.isTemplate { return .black }
        return model.isDark ? .white : Color.black.opacity(0.85)
    }

    var body: some View {
        content
            .padding(.horizontal, 1)
            .frame(height: MenuBarLabelRenderer.height)
            .fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        if let running = model.running {
            runningContent(running)
        } else if let pomodoro = model.pomodoro {
            idleBreakContent(pomodoro)
        } else {
            idleContent
        }
    }

    // MARK: Läuft

    @ViewBuilder
    private func runningContent(_ running: MenuBarLabelModel.Running) -> some View {
        let color = Color(hex: running.colorHex)
        HStack(spacing: 5) {
            switch model.style {
            case .icon:
                MenuBarGlyph(ink: ink, dot: color, dotScale: 1.7)
                trailingText(nil)
            case .compact:
                MenuBarDot(color: color)
                trailingText(model.runningTime)
            case .text:
                MenuBarDot(color: color)
                trailingText(model.showProjectName
                    ? "\(MenuBarLabelModel.shortened(running.name)) · \(model.runningTime)"
                    : model.runningTime)
            case .capsule:
                capsule(running)
            case .ring:
                MenuBarRing(progress: ringProgress(running), color: ringColor(running), track: ringTrack(running))
                trailingText(model.runningTime)
            }
            if model.isOverBudget {
                MenuBarDot(color: Self.overBudget, size: 6)
                    .offset(y: -4)
                    .padding(.leading, -2)
            }
        }
    }

    /// Haupttext plus Pomodoro-Zusatz („· 🍅 23:00“).
    @ViewBuilder
    private func trailingText(_ main: String?) -> some View {
        let pomodoro = model.pomodoroText
        let parts = [main, pomodoro].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(Self.font)
                .foregroundStyle(ink)
                .lineLimit(1)
        }
    }

    private func capsule(_ running: MenuBarLabelModel.Running) -> some View {
        var parts: [String] = []
        if model.showProjectName { parts.append(MenuBarLabelModel.shortened(running.name)) }
        parts.append(model.runningTime)
        if let pomodoro = model.pomodoroText { parts.append(pomodoro) }
        return Text(parts.joined(separator: " · "))
            .font(Self.pillFont)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 18)
            .background(DesignColor.behindWhite(running.colorHex), in: Capsule())
    }

    // Ring: Pomodoro-Phase (Pause grau) > Budget > laufende Stunde.

    private func ringProgress(_ running: MenuBarLabelModel.Running) -> Double {
        if let pomodoro = model.pomodoro { return pomodoro.progress }
        if let budget = running.budgetFraction { return min(1, budget) }
        let minutes = Int(max(0, running.elapsed) / 60) % 60
        return Double(minutes) / 60
    }

    private func ringColor(_ running: MenuBarLabelModel.Running) -> Color {
        let project = Color(hex: running.colorHex)
        if let pomodoro = model.pomodoro { return pomodoro.isBreak ? Self.neutral(dark: model.isDark) : project }
        if let budget = running.budgetFraction {
            if budget > 1 { return Self.overBudget }
            if budget >= 0.8 { return Self.budgetWarning }
        }
        return project
    }

    private func ringTrack(_ running: MenuBarLabelModel.Running) -> Color {
        if model.pomodoro?.isBreak == true { return ink.opacity(0.18) }
        return Color(hex: running.colorHex).opacity(model.isDark ? 0.45 : 0.25)
    }

    // MARK: Pause

    /// Kein Timer, aber Pomodoro-Pause: Tasse + „Pause 07:00“ (Ring-Stil: grauer Ring).
    @ViewBuilder
    private func idleBreakContent(_ pomodoro: MenuBarLabelModel.Pomodoro) -> some View {
        let text = "Pause \(pomodoro.clock)"
        switch model.style {
        case .capsule:
            HStack(spacing: 4) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(text).font(Self.pillFont)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .frame(height: 18)
            .background(ink.opacity(0.2), in: Capsule())
        case .ring:
            HStack(spacing: 5) {
                MenuBarRing(progress: pomodoro.progress, color: ink.opacity(0.75), track: ink.opacity(0.2))
                Text(text).font(Self.font).foregroundStyle(ink)
            }
        case .icon:
            HStack(spacing: 5) {
                MenuBarGlyph(ink: ink, dot: ink)
                Text(text).font(Self.font).foregroundStyle(ink)
            }
        case .compact, .text:
            HStack(spacing: 5) {
                Image(systemName: "cup.and.saucer")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ink)
                Text(text).font(Self.font).foregroundStyle(ink)
            }
        }
    }

    /// Nichts läuft: Glyphe, je nach Einstellung mit Tagessumme.
    @ViewBuilder
    private var idleContent: some View {
        let total = DurationFormat.hourMinute(model.todayTotal)
        if model.idleMode == .symbolAndTotal {
            switch model.style {
            case .capsule:
                Text("Heute \(total)")
                    .font(Self.pillFont)
                    .foregroundStyle(ink)
                    .padding(.horizontal, 8)
                    .frame(height: 18)
                    .background(ink.opacity(0.2), in: Capsule())
            case .text:
                HStack(spacing: 5) {
                    MenuBarGlyph(ink: ink, dot: ink)
                    Text("Heute \(total)").font(Self.font).foregroundStyle(ink)
                }
            case .icon, .compact, .ring:
                HStack(spacing: 5) {
                    MenuBarGlyph(ink: ink, dot: ink)
                    Text(total).font(Self.font).foregroundStyle(ink)
                }
            }
        } else {
            MenuBarGlyph(ink: ink, dot: ink)
        }
    }

    // MARK: Farben

    /// Wie `BudgetPalette` im Widget.
    static let budgetWarning = Color(hex: "#F59E0B")
    static let overBudget = Color(hex: "#EF4444")

    static func neutral(dark: Bool) -> Color {
        dark ? Color.white.opacity(0.55) : Color.black.opacity(0.4)
    }
}

// MARK: - Bausteine

/// Ring-Glyphe wie im App-Symbol: 270°-Bogen, in der Lücke unten rechts ein Punkt.
struct MenuBarGlyph: View {
    var ink: Color
    var dot: Color
    /// Läuft ein Timer, ist der Punkt etwas größer (und in Projektfarbe).
    var dotScale: CGFloat = 1
    var size: CGFloat = 16

    var body: some View {
        let lineWidth = size * 0.13
        let radius = size / 2 - lineWidth / 2 - 0.5
        let dotRadius = lineWidth * 0.62 * dotScale
        let distance = radius * (dotScale > 1 ? 0.84 : 0.9)
        let angle = Angle.degrees(46).radians
        ZStack {
            // Lücke von „3 Uhr“ bis knapp nach „6 Uhr“ (SwiftUI-Winkel im Uhrzeigersinn).
            // `Circle().trim` statt `Canvas`: `Canvas` übernimmt im `ImageRenderer` die Farbe nicht zuverlässig.
            Circle()
                .trim(from: 92.0 / 360, to: 1)
                .stroke(ink, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .fill(dot)
                .frame(width: dotRadius * 2, height: dotRadius * 2)
                .offset(x: cos(angle) * distance, y: sin(angle) * distance)
        }
        .frame(width: size, height: size)
    }
}

/// Farbpunkt in Projektfarbe.
struct MenuBarDot: View {
    var color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// 16-pt-Ring mit Spur und Fortschritt (wie `HourRing` im Widget, kleiner).
struct MenuBarRing: View {
    var progress: Double
    var color: Color
    var track: Color
    var size: CGFloat = 16
    var lineWidth: CGFloat = 2.6

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
    }
}

// MARK: - Erscheinungsbild der Menüleiste

/// Helligkeit der Menüleiste. Sie kann vom System-Erscheinungsbild abweichen (Schreibtischbild),
/// deshalb zählt das Fenster der Statusleiste, sonst die App.
@MainActor
enum MenuBarAppearance {
    static func statusBarWindow() -> NSWindow? {
        // `NSApp` ist vor dem App-Start noch `nil` (z. B. in `TaktApp.init`).
        NSApp?.windows.first { String(describing: type(of: $0)).contains("StatusBarWindow") }
    }

    static func isDark() -> Bool {
        guard let app = NSApp else { return false }
        let appearance = statusBarWindow()?.effectiveAppearance ?? app.effectiveAppearance
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
