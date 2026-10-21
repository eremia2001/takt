import SwiftUI

// Einführung in fünf kurzen Seiten: Willkommen · Erstes Projekt · Widget · Freigaben · Kürzel.
// Rein darstellend (ohne Store/TaktCore), damit sie im Render-Harness läuft; die Anbindung
// (Projekt anlegen, Freigaben, Hilfe) liefert `OnboardingSheet`.

/// Bereits vorhandenes Projekt (für die Seite „Erstes Projekt“).
struct OnboardingProject: Identifiable, Hashable {
    let id: UUID
    let name: String
    let colorHex: String
}

struct OnboardingView<Permissions: View>: View {
    enum Page: Int, CaseIterable {
        case welcome, project, widget, permissions, shortcuts
    }

    var initialPage: Page = .welcome
    var context = HelpContext()
    var existingProjects: [OnboardingProject] = []
    /// Farbauswahl (Projektpalette) und Vorschlag für das neue Projekt.
    var colors: [String] = []
    var suggestedColor: String = "#007AFF"
    /// Legt ein Projekt an; liefert eine Fehlermeldung oder `nil` bei Erfolg.
    var createProject: (_ name: String, _ colorHex: String, _ isBusiness: Bool) -> String? = { _, _, _ in nil }
    var openHelp: (String) -> Void = { _ in }
    /// `true` = „Fertig“, `false` = „Überspringen“.
    var finish: (Bool) -> Void = { _ in }
    @ViewBuilder var permissions: () -> Permissions

    static var size: CGSize { CGSize(width: 620, height: 520) }

    @Environment(\.colorScheme) private var scheme
    @State private var page: Page = .welcome
    @State private var didSetInitialPage = false
    @State private var forward = true

    // Seite „Erstes Projekt“
    @State private var name = ""
    @State private var colorHex: String?
    @State private var isBusiness = true
    @State private var created: [OnboardingProject] = []
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool

    private var theme: DesignTheme { DesignTheme(scheme: scheme) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                content(page)
                    .id(page)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            Divider()
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(theme.window)
        .onAppear {
            guard !didSetInitialPage else { return }
            didSetInitialPage = true
            page = initialPage
        }
    }

    // MARK: Fußzeile

    private var footer: some View {
        HStack(spacing: 10) {
            if page != .shortcuts {
                Button("Überspringen") { finish(false) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Einführung schließen – sie lässt sich über Hilfe › Einführung erneut zeigen öffnen")
            }
            Spacer()
            if page != .welcome {
                Button("Zurück") { go(-1) }
            }
            if page == .shortcuts {
                Button("Fertig") { finish(true) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            } else {
                Button(page == .welcome ? "Los geht’s" : "Weiter") { go(1) }
                    .keyboardShortcut(isNameFocused ? nil : KeyboardShortcut.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 22)
        .frame(height: 64)
        // Seitenpunkte genau in der Mitte, unabhängig von der Breite der Knöpfe.
        .overlay { pageDots }
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(Page.allCases, id: \.self) { item in
                Circle()
                    .fill(item == page ? Color.accentColor : theme.tertiary.opacity(0.6))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Seite \(page.rawValue + 1) von \(Page.allCases.count)")
    }

    private func go(_ delta: Int) {
        guard let next = Page(rawValue: page.rawValue + delta) else { return }
        forward = delta > 0
        withAnimation(.easeInOut(duration: 0.25)) { page = next }
    }

    // MARK: Seiten

    @ViewBuilder
    private func content(_ page: Page) -> some View {
        switch page {
        case .welcome: welcome
        case .project: project
        case .widget: widget
        case .permissions: permissionsPage
        case .shortcuts: shortcuts
        }
    }

    private func pageHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
            Text(subtitle)
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 18)
            TaktGlyph(size: 64)
                .padding(.bottom, 16)
            Text("Willkommen bei Takt")
                .font(.system(size: 26, weight: .bold))
            Text("Takt misst ruhig mit, woran du arbeitest – ein Klick zum Starten, einer zum Stoppen.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 14) {
                feature("timer", "Ein Timer, ein Projekt", "Startest du ein anderes Projekt, endet das vorige von selbst.")
                feature("square.text.square", "Immer im Blick", "Widget, Menüleiste und Mitteilungen zeigen, was gerade läuft.")
                feature("chart.bar", "Klare Berichte", "Stunden, Umsatz, effektiver Satz – und Export für Kunden.")
                feature("lock", "Alles lokal", "Deine Daten bleiben auf diesem Mac. Kein Konto, keine Cloud.")
            }
            .frame(maxWidth: 440, alignment: .leading)
            .padding(.top, 26)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 40)
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(scheme == .dark ? 0.2 : 0.11),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Erstes Projekt

    /// Vorhandene plus hier angelegte Projekte – ohne Doppelte, sobald der Store die neuen liefert.
    private var allProjects: [OnboardingProject] {
        let existing = Set(existingProjects.map { $0.name.lowercased() })
        return existingProjects + created.filter { !existing.contains($0.name.lowercased()) }
    }

    private var project: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageHeader(
                existingProjects.isEmpty || !created.isEmpty ? "Dein erstes Projekt" : "Projekte",
                "Ein Projekt ist alles, wofür du Zeit erfasst: ein Kunde, deine Website, die Steuer. Weitere legst du später unter „Projekte“ (⌘3) an."
            )
            VStack(alignment: .leading, spacing: 14) {
                TextField("Name, z. B. Kundenportal", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($isNameFocused)
                    .onSubmit(create)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Farbe").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(colors, id: \.self) { hex in
                            let isSelected = hex.caseInsensitiveCompare(currentColor) == .orderedSame
                            Button { colorHex = hex } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 22, height: 22)
                                    .overlay(Circle().strokeBorder(.white.opacity(isSelected ? 1 : 0), lineWidth: 2))
                                    .overlay(Circle().strokeBorder(Color(hex: hex).opacity(isSelected ? 1 : 0), lineWidth: 1).padding(-3))
                                    .padding(3)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Farbe \(hex)")
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Art", selection: $isBusiness) {
                        Text("Business").tag(true)
                        Text("Privat").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Text(isBusiness
                         ? "Business: Arbeit für Kunden oder dich selbst – zählt für Umsatz und Wochenziel."
                         : "Privat: Freizeit, Sport, Haushalt – getrennt von der Arbeit ausgewertet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Button("Projekt anlegen", action: create)
                        .buttonStyle(.borderedProminent)
                        .disabled(trimmedName.isEmpty)
                        .keyboardShortcut(isNameFocused ? KeyboardShortcut.defaultAction : nil)
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(16)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))

            if let last = created.last {
                Label("„\(last.name)“ angelegt – in „Heute“ startest du es mit einem Klick.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.green)
            }
            if !allProjects.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(created.isEmpty ? "Schon vorhanden" : "Deine Projekte")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(allProjects.prefix(12)) { item in
                            HStack(spacing: 5) {
                                Circle().fill(Color(hex: item.colorHex)).frame(width: 8, height: 8)
                                Text(item.name).font(.system(size: 12))
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(theme.track, in: Capsule())
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 36)
        .padding(.top, 28)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var currentColor: String { colorHex ?? suggestedColor }

    private func create() {
        let projectName = trimmedName
        guard !projectName.isEmpty else { return }
        if let error = createProject(projectName, currentColor, isBusiness) {
            errorMessage = error
            return
        }
        errorMessage = nil
        withAnimation(.easeOut(duration: 0.2)) {
            created.append(OnboardingProject(id: UUID(), name: projectName, colorHex: currentColor))
        }
        name = ""
        // Nächste freie Farbe vorschlagen.
        let used = Set(allProjects.map { $0.colorHex.uppercased() })
        colorHex = colors.first { !used.contains($0.uppercased()) }
    }

    // MARK: Widget

    private var widget: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageHeader("Widget auf den Schreibtisch", "Das Widget zeigt, was läuft – mit Stopp-Knopf und Schnellstart. So kommt es auf den Schreibtisch:")
            HStack(alignment: .top, spacing: 22) {
                WidgetGalleryIllustration()
                    .frame(width: 236, height: 200)
                VStack(alignment: .leading, spacing: 11) {
                    step(1, "Mit der rechten Maustaste auf eine freie Stelle des Schreibtischs klicken.")
                    step(2, "**Widgets bearbeiten …** wählen.")
                    step(3, "In der Galerie oben „Takt“ ins Suchfeld tippen.")
                    step(4, "Größe wählen, auf den Schreibtisch ziehen, **Fertig**.")
                }
            }
            Text("Alternativ in der Mitteilungszentrale: oben rechts auf Datum und Uhrzeit klicken, ganz nach unten scrollen, „Widgets bearbeiten …“. Stil und Projekt änderst du per Rechtsklick aufs Widget › „Widget bearbeiten“.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Mehr zum Widget in der Hilfe") { openHelp("widget") }
                .buttonStyle(.link)
                .font(.system(size: 12.5, weight: .medium))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 36)
        .padding(.top, 28)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4.5 }
            HelpMarkdown.text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Freigaben

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHeader("Freigaben – alles freiwillig", "macOS fragt für einige Funktionen um Erlaubnis. Erlaube, was du nutzen willst – den Rest kannst du jederzeit später unter Hilfe › Freigaben nachholen.")
            permissions()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 36)
        .padding(.top, 28)
    }

    // MARK: Kürzel

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageHeader("Vier Kürzel zum Merken", "Damit bist du in Takt schneller als mit der Maus. Alle Kürzel stehen auch im Menü und in der Hilfe (⌘?).")
            VStack(spacing: 0) {
                shortcutRow("⌘K", "Befehlspalette", "Projekte starten, Berichte, Einstellungen – einfach lostippen.")
                Divider().padding(.leading, 112)
                shortcutRow("⌘N", "Schnelleingabe", "Zeit in einer Zeile eintragen, z. B. „kunden 9-10:30“.")
                Divider().padding(.leading, 112)
                shortcutRow(context.toggleShortcut, "Timer starten / stoppen", "Überall – auch wenn Takt im Hintergrund ist.")
                Divider().padding(.leading, 112)
                shortcutRow(context.quickEntryShortcut, "Schnelleingabe-Fenster", "Überall – Zeit nachtragen, ohne Takt zu öffnen.")
            }
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
            Text("Die beiden globalen Kurzbefehle änderst du unter Einstellungen › Allgemein.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 36)
        .padding(.top, 28)
    }

    private func shortcutRow(_ keys: String, _ title: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            HelpKeyCap(keys: keys, size: 14)
                .frame(width: 84, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

// MARK: - Illustrationen

/// Takt-Zeichen: 270°-Bogen mit Punkt in der Lücke (wie App-Symbol und Menüleiste).
struct TaktGlyph: View {
    var size: CGFloat = 64

    var body: some View {
        let lineWidth = size * 0.12
        let radius = size / 2 - lineWidth / 2
        let angle = Angle.degrees(46).radians
        ZStack {
            Circle()
                .trim(from: 92.0 / 360, to: 1)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .fill(Color(hex: "#FF9500"))
                .frame(width: lineWidth * 1.5, height: lineWidth * 1.5)
                .offset(x: cos(angle) * radius * 0.86, y: sin(angle) * radius * 0.86)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Schreibtisch mit Kontextmenü „Widgets bearbeiten …“ und einem Takt-Widget – aus Formen gezeichnet.
struct WidgetGalleryIllustration: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack(alignment: .topLeading) {
            // Hintergrundbild
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(
                    colors: dark
                        ? [Color(hex: "#1E2A4A"), Color(hex: "#3B2A55")]
                        : [Color(hex: "#9CC3F5"), Color(hex: "#C9B5F0")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            // Menüleiste
            Rectangle()
                .fill(.white.opacity(dark ? 0.12 : 0.45))
                .frame(height: 12)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12, style: .continuous))

            // Widget oben rechts
            miniWidget
                .offset(x: 146, y: 24)

            // Kontextmenü
            VStack(alignment: .leading, spacing: 0) {
                menuRow("Neuer Ordner", highlighted: false)
                Divider().padding(.horizontal, 6).padding(.vertical, 2)
                menuRow("Widgets bearbeiten …", highlighted: true)
                menuRow("Hintergrundbild …", highlighted: false)
            }
            .padding(4)
            .frame(width: 138)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            .offset(x: 22, y: 92)

            // Mauszeiger
            Image(systemName: "cursorarrow")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.black)
                .shadow(color: .white, radius: 0.5)
                .offset(x: 150, y: 124)
        }
        .accessibilityElement()
        .accessibilityLabel("Rechtsklick auf den Schreibtisch, dann „Widgets bearbeiten …“")
    }

    private func menuRow(_ title: String, highlighted: Bool) -> some View {
        Text(title)
            .font(.system(size: 10.5, weight: highlighted ? .medium : .regular))
            .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: 19, alignment: .leading)
            .background(highlighted ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var miniWidget: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle().fill(Color(hex: "#30B0C7")).frame(width: 7, height: 7)
                Text("Website").font(.system(size: 9, weight: .semibold)).lineLimit(1)
            }
            Text("1:24")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: "#30B0C7").opacity(0.75))
                .frame(width: 30, height: 3)
        }
        .padding(8)
        .frame(width: 70, height: 70, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}
