import Foundation

// Inhalt der Takt-Hilfe als strukturierte Daten (Überschriften, Absätze, Schritte, Kürzel …).
// Bewusst ohne Store-, AppKit- und TaktCore-Abhängigkeit: läuft offline, im Render-Harness und
// liefert zugleich die Befehle „Hilfe: …“ der Befehlspalette.
//
// Platzhalter in Texten: `{toggle}` = globaler Kurzbefehl Start/Stopp (Standard ⌃⌥⌘T),
// `{quick}` = Kurzbefehl des Schnelleingabe-Fensters (Standard ⌃⌥⌘N). `HelpContext` ersetzt sie
// durch die eingestellten Kombinationen.

/// Ziel eines Knopfs „Dort hin“ bzw. eines Links in der Hilfe.
enum HelpDestination: Hashable {
    case section(AppSection)
    /// Einstellungen-Reiter (Kennung wie in `SettingsView`, z. B. "focus").
    case settings(String)
    case commandPalette
    case quickEntryPanel
    case onboarding
    case helpTopic(String)
    /// Aktion über `AppNavigator` (Export, Import, Neues Projekt …).
    case action(AppAction)
    /// Datenbankordner im Finder zeigen.
    case revealDatabase
    /// Adresse in den Systemeinstellungen (`x-apple.systempreferences:…`).
    case systemSettings(String)

    /// Kurzer Ortsname für Knopf und Tooltip.
    var title: String {
        switch self {
        case .section(let section): section.title
        case .settings(let tab): "Einstellungen › \(HelpContent.settingsTabTitle(tab))"
        case .commandPalette: "Befehlspalette"
        case .quickEntryPanel: "Schnelleingabe-Fenster"
        case .onboarding: "Einführung"
        case .helpTopic(let id): HelpContent.topic(id).title
        case .action(let action):
            switch action {
            case .exportEntriesCSV: "Einträge als CSV"
            case .exportSummaryCSV: "Zusammenfassung als CSV"
            case .exportTimesheetPDF: "Timesheet als PDF"
            case .importToggl: "Toggl-Import"
            case .planBlock: "Block planen"
            case .newProject: "Neues Projekt"
            case .newEntry: "Neuer Eintrag"
            }
        case .revealDatabase: "Datenbank im Finder"
        case .systemSettings: "Systemeinstellungen"
        }
    }
}

/// Tastaturkürzel: Tasten und was sie tun.
struct HelpShortcut: Hashable {
    let keys: String
    let text: String
}

/// Beispiel-Eingabe und Ergebnis (Befehlspalette, Schnelleingabe).
struct HelpExample: Hashable {
    let input: String
    let result: String
}

/// Baustein eines Hilfe-Themas. Texte dürfen einfaches Markdown enthalten (`**fett**`, `` `Code` ``).
enum HelpBlock: Hashable {
    case heading(String)
    case paragraph(String)
    case bullets([String])
    /// „So geht's“: nummerierte Schritte mit optionalem Titel.
    case steps(String?, [String])
    /// Tabelle mit Kürzel-Kapseln; Titel optional.
    case shortcuts(String?, [HelpShortcut])
    case examples([HelpExample])
    case tip(String)
    case note(String)
    case link(String, HelpDestination)
    /// Lebende Bausteine, die die Oberfläche selbst füllt.
    case live(Live)

    enum Live: Hashable {
        /// Status und Knöpfe aller vier Freigaben.
        case permissions
        /// Ort der Datenbank und vorhandene Sicherungen.
        case dataLocation
    }

    /// Reiner Text für die Suche.
    var searchText: String {
        switch self {
        case .heading(let text), .paragraph(let text), .tip(let text), .note(let text): text
        case .bullets(let items): items.joined(separator: " ")
        case .steps(let title, let items): ([title ?? ""] + items).joined(separator: " ")
        case .shortcuts(let title, let items): ([title ?? ""] + items.map { "\($0.keys) \($0.text)" }).joined(separator: " ")
        case .examples(let items): items.map { "\($0.input) \($0.result)" }.joined(separator: " ")
        case .link(let title, _): title
        case .live(.permissions): "Freigaben Mitteilungen Automation Spotify Musik Kalender Termine Bedienungshilfen Fenstertitel Medientaste erlauben"
        case .live(.dataLocation): "Datenbank Ordner Sicherung takt.sqlite"
        }
    }
}

/// Ein Thema der Hilfe.
struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    /// SF Symbol.
    let icon: String
    /// Ein Satz unter dem Titel.
    let summary: String
    /// Zusätzliche Suchbegriffe.
    var keywords: [String] = []
    /// Hauptziel für den Knopf „Dort hin“ oben rechts.
    var destination: HelpDestination?
    let blocks: [HelpBlock]

    /// Gesamter Text für die Suche (normalisiert).
    var searchIndex: String {
        HelpContent.normalize(([title, summary] + keywords + blocks.map(\.searchText)).joined(separator: " "))
    }
}

/// Eingestellte Kurzbefehle für die Platzhalter `{toggle}` und `{quick}`.
struct HelpContext: Equatable {
    var toggleShortcut = "⌃⌥⌘T"
    var quickEntryShortcut = "⌃⌥⌘N"

    func resolve(_ text: String) -> String {
        text.replacingOccurrences(of: "{toggle}", with: toggleShortcut)
            .replacingOccurrences(of: "{quick}", with: quickEntryShortcut)
    }
}

enum HelpContent {
    static let defaultTopicID = "start"

    /// Weitere Kennungen (z. B. aus „Mehr in der Hilfe →“) → kanonisches Thema.
    static let aliases: [String: String] = [
        "general": "menubar", "today": "start", "projects": "billing", "timer": "focus",
        "export": "reports", "pomodoro": "focus", "privacy": "permissions", "help": "start",
        "commands": "palette", "keyboard": "shortcuts", "backup": "data", "menuBar": "menubar",
        "quickEntry": "quickentry", "idle": "focus", "budget": "billing",
    ]

    /// Thema zur Kennung (Aliasse aufgelöst); unbekannt → „Erste Schritte“.
    static func topic(_ id: String?) -> HelpTopic {
        let key = id.map { aliases[$0] ?? aliases[$0.lowercased()] ?? $0.lowercased() } ?? defaultTopicID
        return topics.first { $0.id == key } ?? topics[0]
    }

    /// Themen, auf die die Suche passt (alle Wörter müssen vorkommen); leer = alle.
    static func search(_ query: String) -> [HelpTopic] {
        let tokens = normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return topics }
        return topics
            .map { topic -> (HelpTopic, Int) in
                let index = topic.searchIndex
                let title = normalize(topic.title + " " + topic.keywords.joined(separator: " "))
                guard tokens.allSatisfy({ index.contains($0) }) else { return (topic, -1) }
                // Treffer im Titel oder in den Suchbegriffen zuerst.
                return (topic, tokens.filter { title.contains($0) }.count)
            }
            .filter { $0.1 >= 0 }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }

    static func settingsTabTitle(_ id: String) -> String {
        switch id {
        case "general": "Allgemein"
        case "notifications": "Mitteilungen"
        case "music": "Musik"
        case "focus": "Fokus"
        case "widget": "Widget"
        case "billing": "Abrechnung"
        case "calendar": "Kalender"
        case "activity": "Aktivität"
        default: id
        }
    }

    // MARK: Tastaturkürzel (eine Quelle für Hilfe und Einführung)

    static let globalShortcuts: [HelpShortcut] = [
        HelpShortcut(keys: "{toggle}", text: "Timer starten oder stoppen – in jeder App (letztes Projekt)"),
        HelpShortcut(keys: "{quick}", text: "Schnelleingabe-Fenster öffnen – in jeder App"),
    ]

    static let windowShortcuts: [HelpShortcut] = [
        HelpShortcut(keys: "⌘K", text: "Befehlspalette öffnen und schließen"),
        HelpShortcut(keys: "⌘N", text: "Schnelleingabe (in „Heute“ das Feld, sonst das Fenster)"),
        HelpShortcut(keys: "⌘.", text: "Laufenden Timer stoppen"),
        HelpShortcut(keys: "⌘1", text: "Heute"),
        HelpShortcut(keys: "⌘2", text: "Berichte"),
        HelpShortcut(keys: "⌘3", text: "Projekte"),
        HelpShortcut(keys: "⌥⌘1 … ⌥⌘4", text: "Bericht: Tag, Woche, Monat, Jahr"),
        HelpShortcut(keys: "⌘,", text: "Einstellungen"),
        HelpShortcut(keys: "⌘?", text: "Diese Hilfe"),
    ]

    static let paletteShortcuts: [HelpShortcut] = [
        HelpShortcut(keys: "↑ ↓", text: "Treffer wählen"),
        HelpShortcut(keys: "↩", text: "Ausführen"),
        HelpShortcut(keys: "⌘1 … ⌘9", text: "Treffer 1–9 direkt ausführen"),
        HelpShortcut(keys: "esc", text: "Rückfrage abbrechen, dann Suchtext leeren, dann schließen"),
    ]

    static let entryShortcuts: [HelpShortcut] = [
        HelpShortcut(keys: "↩", text: "Eingabe übernehmen"),
        HelpShortcut(keys: "esc", text: "Feld leeren; ein zweites Mal verlässt das Feld bzw. schließt das Fenster"),
    ]

    // MARK: Themen

    static let topics: [HelpTopic] = [
        start, shortcuts, palette, quickEntry, widget, menuBar, music, focus,
        billing, reports, calendar, activity, notifications, permissions, data,
    ]

    static let start = HelpTopic(
        id: "start",
        title: "Erste Schritte",
        icon: "flag",
        summary: "Projekt anlegen, Timer starten und stoppen – in zwei Minuten startklar.",
        keywords: ["anfangen", "einstieg", "grundlagen", "timer", "start", "stopp", "nächster schritt"],
        destination: .section(.projects),
        blocks: [
            .paragraph("Takt misst, woran du gerade arbeitest. Es läuft immer **nur ein Timer**: Startest du ein anderes Projekt, endet der vorige von selbst."),
            .steps("Projekt anlegen", [
                "Oben im Fenster auf **Projekte** klicken (⌘3).",
                "Rechts oben auf **+ Projekt** klicken.",
                "Namen eingeben, eine Farbe wählen und **Business** oder **Privat** einstellen.",
                "Auf **Anlegen** klicken.",
            ]),
            .steps("Timer starten und stoppen", [
                "Zu **Heute** wechseln (⌘1).",
                "Auf die Kapsel eines Projekts klicken – der Timer läuft, die große Karte färbt sich.",
                "Zum Stoppen in der Karte auf **Stoppen** klicken oder ⌘. drücken.",
                "Optional notieren, was als Nächstes kommt, und mit ↩ bestätigen.",
            ]),
            .heading("Nächster Schritt"),
            .paragraph("Beim Stoppen kannst du einen kurzen Satz notieren, z. B. „Login-Fehler nachstellen“. Beim nächsten Start dieses Projekts zeigt Takt die Notiz in der Karte – so findest du sofort wieder hinein."),
            .heading("Starten geht auch ohne Fenster"),
            .bullets([
                "**Menüleiste:** oben rechts auf das Takt-Symbol klicken, dann auf ein Projekt.",
                "**Widget:** auf dem Schreibtisch oder in der Mitteilungszentrale.",
                "**Kurzbefehl {toggle}:** startet das zuletzt genutzte Projekt bzw. stoppt den laufenden Timer – in jeder App.",
            ]),
            .steps("Widget hinzufügen", [
                "Mit der rechten Maustaste auf eine freie Stelle des Schreibtischs klicken.",
                "**Widgets bearbeiten …** wählen.",
                "Im Suchfeld der Galerie „Takt“ eingeben.",
                "Eine Größe wählen und das Widget auf den Schreibtisch ziehen, dann **Fertig**.",
            ]),
            .tip("Vergessen zu starten? Mit der Schnelleingabe trägst du Zeit nachträglich ein: `Kundenportal 9-10:30`."),
            .link("Mehr zum Widget", .helpTopic("widget")),
            .link("Einführung erneut zeigen", .onboarding),
        ]
    )

    static let shortcuts = HelpTopic(
        id: "shortcuts",
        title: "Tastaturkürzel",
        icon: "keyboard",
        summary: "Alle Kürzel auf einen Blick. Die zwei globalen Kürzel wirken in jeder App.",
        keywords: ["kurzbefehl", "tasten", "hotkey", "shortcut", "tastatur"],
        destination: .settings("general"),
        blocks: [
            .shortcuts("Überall (auch wenn Takt im Hintergrund ist)", globalShortcuts),
            .paragraph("Die beiden globalen Kurzbefehle kannst du unter **Einstellungen › Allgemein** ändern oder abschalten. Ist eine Kombination schon von einer anderen App belegt, zeigt Takt dort einen Hinweis."),
            .shortcuts("Im Hauptfenster", windowShortcuts),
            .shortcuts("In der Befehlspalette", paletteShortcuts),
            .shortcuts("In der Schnelleingabe", entryShortcuts),
            .tip("Fast alle Kürzel stehen auch in der Menüleiste oben: unter **Timer**, **Darstellung**, **Ablage** und **Hilfe**. Dort kannst du jederzeit nachsehen."),
        ]
    )

    static let palette = HelpTopic(
        id: "palette",
        title: "Befehlspalette ⌘K",
        icon: "command",
        summary: "Alles per Tastatur: tippen, ↩ – fertig.",
        keywords: ["befehle", "suche", "spotlight", "cmd k", "palette", "tastatur"],
        destination: .commandPalette,
        blocks: [
            .paragraph("Die Befehlspalette ist der schnellste Weg zu fast allem: Projekte starten, Timer stoppen, Bereiche wechseln, Berichte, Export, Einstellungen und Hilfe."),
            .bullets([
                "**Öffnen:** ⌘K im Hauptfenster, der Knopf **Befehle** oben im Fenster oder **Timer › Befehle** im Menü.",
                "Aus der **Menüleiste**: Zeile „Befehle … ⌘K“ im Takt-Fenster.",
                "**Schließen:** noch einmal ⌘K, esc oder daneben klicken.",
            ]),
            .heading("Beispiele"),
            .examples([
                HelpExample(input: "kun", result: "„Starten: Kundenportal“ – ein Wortanfang genügt"),
                HelpExample(input: "stop", result: "Laufenden Timer stoppen"),
                HelpExample(input: "bw", result: "„Bericht: Woche“ – Anfangsbuchstaben gehen auch"),
                HelpExample(input: "csv", result: "Einträge oder Zusammenfassung als CSV sichern"),
                HelpExample(input: "einst mus", result: "Einstellungen › Musik öffnen"),
                HelpExample(input: "kunden 9-10:30 #meeting", result: "Trägt 09:00–10:30 für Kundenportal mit Tag „meeting“ ein"),
                HelpExample(input: "hilfe pomodoro", result: "Öffnet dieses Handbuch beim Thema Fokus"),
            ]),
            .shortcuts("Tasten", paletteShortcuts),
            .tip("Ohne Suchtext stehen oben die zuletzt genutzten Befehle. Archivieren und einzelne Einstellungs-Reiter erscheinen erst, wenn du danach suchst."),
            .paragraph("Enthält dein Text Ziffern oder ein `#`, versteht die Palette ihn auch als **Schnelleingabe** – der Treffer „Eintragen: …“ steht dann ganz oben."),
            .link("Befehlspalette jetzt öffnen", .commandPalette),
        ]
    )

    static let quickEntry = HelpTopic(
        id: "quickentry",
        title: "Schnelleingabe",
        icon: "text.cursor",
        summary: "Eine Zeile statt Formular: Projekt, Zeit, Tag und Notiz in einem Rutsch.",
        keywords: ["nachtragen", "eintragen", "grammatik", "eingabe", "quick entry", "zeit nachtragen"],
        destination: .quickEntryPanel,
        blocks: [
            .paragraph("Du schreibst, was du gemacht hast – Takt erkennt Projekt, Uhrzeit, Datum, Tag und Notiz. Eine Vorschauzeile zeigt vor dem ↩, was passieren wird."),
            .heading("Wo?"),
            .bullets([
                "**In „Heute“:** Feld unter den Projekt-Kapseln, ⌘N setzt den Cursor hinein.",
                "**Überall:** {quick} öffnet ein schwebendes Fenster, auch wenn eine andere App vorne ist.",
                "**Menüleiste:** Feld über der Projektliste im Takt-Fenster.",
                "**Befehlspalette:** einfach losschreiben, z. B. `garten 14-15`.",
            ]),
            .heading("Aufbau"),
            .paragraph("`[Datum] Projekt [Zeit] [#Tag] [Notiz …]` – nur das Projekt ist Pflicht. Der Projektname darf abgekürzt sein; was übrig bleibt, wird zur Notiz. Groß- und Kleinschreibung ist egal."),
            .examples([
                HelpExample(input: "Kundenportal 9:00-10:30 Review", result: "Heute 09:00–10:30, Notiz „Review“"),
                HelpExample(input: "kunden 9-10:30 #meeting Standup", result: "Kundenportal, Tag „meeting“, Notiz „Standup“"),
                HelpExample(input: "Garten 14:00 bis 15:15", result: "Zeitspanne mit „bis“ (auch: von 8 bis 9:45 Uhr)"),
                HelpExample(input: "Website 1h30", result: "1:30 Stunden bis jetzt (auch 45m, 90min, 1,5h, 2 Std)"),
                HelpExample(input: "Steuer gestern 20-21", result: "Gestern 20:00–21:00 (auch vorgestern)"),
                HelpExample(input: "Mo 9-11 Kundenportal", result: "Letzter Montag – heute eingeschlossen"),
                HelpExample(input: "19.10. 9-10 Garten", result: "Ein bestimmter Tag (nie in der Zukunft)"),
                HelpExample(input: "Website", result: "Startet den Timer jetzt"),
                HelpExample(input: "Website seit 9:30", result: "Timer läuft rückwirkend ab 09:30"),
            ]),
            .bullets([
                "**Über Mitternacht:** `23-1` ist 23:00 bis 01:00 am nächsten Tag.",
                "**Mehrdeutig?** Passen zwei Projekte gleich gut, zeigt Takt beide als Kapseln – klicken wählt.",
                "**Tag** (`#meeting`) ist eine freie Kennzeichnung. Berichte zeigen später, wie viel Zeit je Tag zusammenkam.",
            ]),
            .shortcuts("Tasten", entryShortcuts),
            .link("Schnelleingabe-Fenster öffnen", .quickEntryPanel),
        ]
    )

    static let widget = HelpTopic(
        id: "widget",
        title: "Widget",
        icon: "square.text.square",
        summary: "Auf dem Schreibtisch sehen, was läuft – und mit einem Klick wechseln.",
        keywords: ["schreibtisch", "desktop", "mitteilungszentrale", "stil", "ring", "farbfläche", "ein-projekt", "geplanter block"],
        destination: .settings("widget"),
        blocks: [
            .paragraph("Das Widget zeigt, was gerade läuft: Projekt, Dauer, Stopp-Knopf. Läuft nichts, bietet es die zuletzt genutzten Projekte zum Starten an. Ein Klick auf die freie Fläche öffnet Takt."),
            .steps("Widget hinzufügen", [
                "Mit der rechten Maustaste auf eine freie Stelle des Schreibtischs klicken.",
                "**Widgets bearbeiten …** wählen – unten öffnet sich die Widget-Galerie.",
                "Oben in der Galerie „Takt“ ins Suchfeld tippen (oder links in der Liste **Takt** wählen).",
                "Eine Größe wählen und das Widget auf den Schreibtisch ziehen.",
                "Auf **Fertig** klicken.",
            ]),
            .tip("Lieber in der Mitteilungszentrale? Oben rechts auf Datum und Uhrzeit klicken, ganz nach unten scrollen und **Widgets bearbeiten …** wählen."),
            .heading("Größen"),
            .bullets([
                "**Klein:** laufendes Projekt mit Dauer und Stopp; im Ruhezustand bis zu drei Start-Knöpfe.",
                "**Mittel:** dazu „Wechseln zu“, nächster Schritt, Tagessumme und geplanter Block.",
                "**Groß:** dazu die Tagesleiste von 8 bis 19 Uhr und alle Projekte.",
            ]),
            .steps("Stil und Projekt wählen („Widget bearbeiten“)", [
                "Mit der rechten Maustaste auf das Widget klicken.",
                "**Widget bearbeiten** wählen.",
                "**Stil:** Standard, Schlicht, Farbfläche oder Ring. „Standard“ folgt Einstellungen › Widget.",
                "**Projekt:** leer lassen für alle Projekte – oder ein Projekt wählen.",
            ]),
            .heading("Festes Projekt"),
            .paragraph("Mit gewähltem Projekt wird das Widget zum **Ein-Projekt-Widget**: Es zeigt nur dieses Projekt mit Tagessumme und Budget. Läuft gerade ein anderes, steht dort „Läuft: anderes Projekt“; der Start-Knopf wechselt dann. Praktisch: ein Widget je Kunde."),
            .heading("Geplanter Block"),
            .paragraph("Planst du in „Heute“ unter der Karte einen **Block** (z. B. „14:00 · Kundenportal“), zeigt das Widget ihn mit ▶︎ an. Zum Beginn kommt eine Mitteilung, falls dann nichts läuft. Planen geht auch über **Timer › Block planen …**."),
            .heading("Pomodoro und Budget"),
            .paragraph("Mit Pomodoro zeigt ein dünner Strich, wie viel von der Arbeitseinheit vorbei ist. Hat das Projekt ein Stundenbudget, zeigt der Stil **Ring** den Verbrauch – ab 80 % orange, darüber rot."),
            .note("Zeigt das Widget nach einem Update noch das alte Aussehen, entferne es einmal und füge es neu hinzu."),
            .link("Einstellungen › Widget öffnen", .settings("widget")),
        ]
    )

    static let menuBar = HelpTopic(
        id: "menubar",
        title: "Menüleiste",
        icon: "menubar.rectangle",
        summary: "Takt oben rechts: Timer sehen, Projekte starten, ohne das Fenster zu öffnen.",
        keywords: ["menüleiste", "statusleiste", "dock", "symbol", "notch", "bartender", "ice", "kapsel", "allgemein"],
        destination: .settings("general"),
        blocks: [
            .paragraph("Ein Klick auf das Takt-Symbol in der Menüleiste öffnet ein kleines Fenster: oben die Karte mit dem laufenden Timer, darunter alle Projekte (Klick = Start), die Schnelleingabe und „Befehle … ⌘K“."),
            .heading("Stile"),
            .bullets([
                "**Symbol:** nur das Takt-Zeichen, der Punkt färbt sich beim Laufen.",
                "**Kompakt:** Farbpunkt und Dauer, z. B. „● 1:24“.",
                "**Text** (Standard): Farbpunkt, Projektname und Dauer.",
                "**Kapsel:** farbige Pille mit weißer Schrift.",
                "**Ring:** Ring mit Dauer; zeigt Pomodoro, Budget oder die laufende Stunde.",
            ]),
            .steps("Stil ändern", [
                "**Einstellungen › Allgemein** öffnen (⌘,).",
                "Im Bereich **Menüleiste** den Stil wählen – die Vorschau zeigt „Läuft“ und „Pause“.",
                "Unter **Wenn nichts läuft** festlegen: nur Symbol, Symbol mit Tagessumme oder ganz ausblenden.",
            ]),
            .heading("Dock-Symbol ausblenden"),
            .paragraph("Unter **Einstellungen › Allgemein** kannst du das Dock-Symbol ausblenden. Das geht nur zusammen mit der Menüleiste – sonst wäre Takt nicht mehr erreichbar. Das Fenster öffnest du dann über die Menüleiste: **Takt öffnen**."),
            .heading("Symbol verschwunden?"),
            .bullets([
                "Bei vielen Symbolen verdeckt die Kamera-Aussparung („Notch“) manche davon. Weniger Symbole oder ein kürzerer Stil (Symbol, Kompakt) helfen.",
                "**Menüleisten-Manager** wie Bartender, Ice oder Hidden Bar können Takt verstecken. Dort Takt als „immer sichtbar“ einstellen.",
                "Mit gedrückter ⌘-Taste lassen sich Symbole verschieben. Ziehst du Takt heraus, schaltet sich „In der Menüleiste anzeigen“ aus – in den Einstellungen wieder einschalten.",
            ]),
            .link("Einstellungen › Allgemein öffnen", .settings("general")),
        ]
    )

    static let music = HelpTopic(
        id: "music",
        title: "Musik",
        icon: "music.note",
        summary: "Timer starten, Musik läuft. Timer stoppen, Musik pausiert.",
        keywords: ["spotify", "apple music", "youtube", "playlist", "browser", "medientaste", "automation"],
        destination: .settings("music"),
        blocks: [
            .paragraph("Takt kann beim Start eines Timers Musik spielen und beim Stoppen pausieren. Jedes Projekt kann eine eigene Quelle haben; sonst gilt die **Standard-Quelle** aus den Einstellungen."),
            .steps("Einrichten", [
                "**Einstellungen › Musik** öffnen und die Steuerung einschalten.",
                "Den bevorzugten Anbieter wählen: Spotify, Apple Music oder Browser.",
                "Eine Standard-Quelle eintragen: einen Link oder den Namen einer Playlist.",
                "Für einzelne Projekte: **Projekte** › Projekt bearbeiten › Feld „Musik“.",
            ]),
            .heading("Spotify"),
            .paragraph("In Spotify bei einer Playlist **Teilen › Link kopieren** wählen und den Link einfügen (oder eine `spotify:`-Adresse). Takt startet die Spotify-App bei Bedarf selbst."),
            .heading("Apple Music: Mediathek oder Katalog"),
            .bullets([
                "**Playlists aus deiner Mediathek** spielt Takt zuverlässig ab. Schreibweise: `Apple Music: Fokus` oder `applemusic:playlist:Fokus`.",
                "**Links aus dem Katalog** (`music.apple.com/…`) öffnet Takt nur in der Musik-App – abspielen musst du dort selbst.",
                "Tipp: Katalog-Playlist in der Musik-App zur Mediathek hinzufügen und dann den Namen eintragen.",
            ]),
            .heading("Browser und YouTube"),
            .paragraph("YouTube-, YouTube-Music- und andere Web-Links öffnet Takt im Standardbrowser. Den Browser kann Takt nicht direkt steuern: Zum Pausieren sendet es die Medientaste Play/Pause. Dafür braucht Takt die Freigabe **Bedienungshilfen**. Die Taste wirkt auf das, was macOS gerade als „Aktuell läuft“ führt."),
            .heading("Freigabe „Automation“"),
            .paragraph("Beim ersten Abspielen fragt macOS, ob Takt Spotify bzw. Musik steuern darf. Versehentlich abgelehnt? **Systemeinstellungen › Datenschutz & Sicherheit › Automation › Takt** und dort den Schalter einschalten."),
            .bullets([
                "Stoppen pausiert die Musik, die Pausenerinnerung auf Wunsch auch.",
                "„Laufende Musik übernehmen“ aus: Spielt schon etwas, bleibt es dabei.",
            ]),
            .link("Freigaben prüfen", .helpTopic("permissions")),
            .link("Einstellungen › Musik öffnen", .settings("music")),
        ]
    )

    static let focus = HelpTopic(
        id: "focus",
        title: "Fokus",
        icon: "cup.and.saucer",
        summary: "Pausen nicht vergessen, Leerlauf abziehen, vergessene Timer bemerken.",
        keywords: ["pomodoro", "pause", "pausenerinnerung", "leerlauf", "idle", "vergessener timer", "konzentration", "tomate"],
        destination: .settings("focus"),
        blocks: [
            .heading("Pausenerinnerung"),
            .paragraph("Arbeitest du lange am Stück (Standard 75 Minuten), kommt eine Mitteilung. Auf Wunsch pausiert dabei die Musik. Im Widget zeigt ein dünner Strich, wie nah die nächste Pause ist."),
            .steps("Pomodoro Schritt für Schritt", [
                "**Einstellungen › Fokus** öffnen und **Pomodoro** einschalten.",
                "Längen wählen: Arbeit (Standard 50 Min), Pause (10), lange Pause (20) und nach wie vielen Einheiten die lange Pause kommt (4).",
                "Einen Timer starten – die erste Arbeitseinheit beginnt.",
                "Die Menüleiste zeigt die Restzeit, z. B. „🍅 23:00“.",
                "Am Ende kommt „Pomodoro: Pause (10 Min)“. Ist „Timer am Ende stoppen“ an, stoppt Takt den Timer.",
                "Nach der Pause fragt Takt „Pause vorbei – weiter mit …?“. **Weiter** startet das letzte Projekt.",
            ]),
            .bullets([
                "Im Menüleisten-Fenster überspringt **Phase überspringen** die aktuelle Arbeit oder Pause.",
                "Stoppst du vor Ablauf, zählt die Einheit nicht. Projektwechsel unterbrechen sie nicht.",
                "Solange Pomodoro an ist, ersetzt es die normale Pausenerinnerung.",
            ]),
            .heading("Leerlauf"),
            .paragraph("Läuft ein Timer und du bist eine Weile nicht am Mac (Standard 10 Minuten ohne Maus und Tastatur), fragt Takt bei deiner Rückkehr, was mit der Zeit passieren soll:"),
            .bullets([
                "**Abziehen:** Die Abwesenheit wird herausgeschnitten, der Timer läuft weiter.",
                "**Behalten:** Die Zeit zählt mit (z. B. Telefonat, Besprechung).",
                "**Bei Leerlauf stoppen:** Der Eintrag endet zu Beginn der Abwesenheit.",
            ]),
            .paragraph("Ruhezustand und Bildschirmsperre zählen ebenfalls als Leerlauf."),
            .heading("Vergessener Timer"),
            .paragraph("Läuft ein Timer länger als eingestellt (Standard 8 Stunden), fragt Takt nach: **Läuft weiter**, **Jetzt stoppen** oder **Stoppen um …** – dann stoppt Takt und zeigt „Heute“, damit du das Ende im Eintrag korrigierst."),
            .link("Einstellungen › Fokus öffnen", .settings("focus")),
        ]
    )

    static let billing = HelpTopic(
        id: "billing",
        title: "Projekte & Abrechnung",
        icon: "eurosign.circle",
        summary: "Business oder privat, Kunde, Stundensatz, Budget, Rundung, Wochenziel.",
        keywords: ["projekt", "kunde", "stundensatz", "satz", "abrechenbar", "budget", "rundung", "wochenziel", "freie tage", "urlaub", "archivieren", "business", "privat"],
        destination: .section(.projects),
        blocks: [
            .paragraph("Alles, was abgerechnet wird, hängt am Projekt. Bearbeiten: **Projekte** (⌘3) › Doppelklick auf ein Projekt oder Rechtsklick › Bearbeiten."),
            .bullets([
                "**Business / Privat:** trennt Arbeit und Freizeit. Berichte zeigen beides getrennt; der effektive Satz zählt nur Business.",
                "**Kunde:** freier Text. Gleiche Kunden werden im Jahresbericht und im Timesheet zusammengefasst.",
                "**Stundensatz:** pro Projekt. Leer = Standard-Stundensatz aus Einstellungen › Abrechnung.",
                "**Abrechenbar:** Vorgabe für alle Einträge (bei Business an). Einzelne Einträge können abweichen.",
                "**Budget:** Stundenbudget, z. B. 40 h. Die Liste zeigt „12:30 / 40 h“; bei 80 % und 100 % kommt eine Mitteilung.",
            ]),
            .heading("Rundung"),
            .paragraph("Unter **Einstellungen › Abrechnung** rundest du auf 6, 15 oder 30 Minuten **auf** – je Eintrag. Beispiel: 7 Minuten mit 15-Minuten-Rundung zählen als 0:15. Beträge beruhen immer auf der gerundeten, abrechenbaren Zeit; die echte Zeit bleibt daneben sichtbar."),
            .heading("Wochenziel"),
            .paragraph("Ziel in abrechenbaren Stunden pro Woche. Es passt sich freien Tagen an: Bei 40 h und einem Urlaubstag gelten 32 h. Berichte › Woche zeigt den Fortschritt als Balken."),
            .heading("Freie Tage"),
            .paragraph("Urlaub, Krank, Feiertag oder Sonstiges. Markieren: in „Heute“ oben rechts **Heute frei …** (wenn nichts läuft) oder in **Berichte › Freie Tage …**. Freie Tage zählen nicht als Arbeitstage."),
            .heading("Archivieren statt löschen"),
            .paragraph("Ein archiviertes Projekt verschwindet aus „Heute“, Menüleiste und Widget. Seine Einträge bleiben in den Berichten. Unter **Projekte › Archiv** lässt es sich wiederherstellen."),
            .link("Neues Projekt anlegen", .action(.newProject)),
            .link("Einstellungen › Abrechnung öffnen", .settings("billing")),
        ]
    )

    static let reports = HelpTopic(
        id: "reports",
        title: "Berichte & Export",
        icon: "chart.bar",
        summary: "Wohin die Zeit ging – und wie du sie als CSV, PDF oder aus Toggl bekommst.",
        keywords: ["bericht", "auswertung", "kennzahlen", "effektiver satz", "tags", "csv", "excel", "timesheet", "pdf", "toggl", "import", "jahr", "export"],
        destination: .section(.reports),
        blocks: [
            .heading("Zeiträume"),
            .paragraph("Oben in **Berichte** (⌘2): Tag, Woche, Monat, Jahr oder ein freier Zeitraum. ‹ › blättert, **Heute** springt zurück. Wochen beginnen montags. Direkt: ⌥⌘1 Tag, ⌥⌘2 Woche, ⌥⌘3 Monat, ⌥⌘4 Jahr."),
            .heading("Kennzahlen"),
            .bullets([
                "**Gesamt** und **Abrechenbar** (gerundet, Grundlage der Beträge).",
                "**Umsatz:** abrechenbare Zeit × Stundensatz.",
                "**Fokus:** Projektwechsel pro Tag und längster Block am Stück.",
                "**Ø pro Arbeitstag:** Montag bis Freitag, ohne freie Tage.",
            ]),
            .heading("Effektiver Satz"),
            .paragraph("Was eine **investierte** Stunde wirklich einbringt: Umsatz geteilt durch die gesamte Business-Zeit, auch die nicht abrechenbare (Akquise, Angebote, Pflege). Der **nominale** Satz rechnet nur mit abgerechneten Stunden."),
            .examples([
                HelpExample(input: "10 h gearbeitet", result: "davon 8 h × 100 € abgerechnet = 800 €"),
                HelpExample(input: "nominal", result: "800 € ÷ 8 h = 100 €/h"),
                HelpExample(input: "effektiv", result: "800 € ÷ 10 h = 80 €/h – orange, weil mehr als 15 % darunter"),
            ]),
            .heading("Tags"),
            .paragraph("Eine Projektzeile anklicken klappt sie auf: zuerst „nach Tag“ (z. B. Meeting, Bugfix), darunter die Einträge. Tags vergibst du beim Stoppen, im Eintrag oder mit `#tag` in der Schnelleingabe."),
            .heading("Export"),
            .bullets([
                "**Einträge als CSV** – jede Zeile ein Eintrag; passt für deutsches Excel (Semikolon, Dezimalkomma).",
                "**Zusammenfassung als CSV** – Summen je Projekt.",
                "**Jahr als CSV** – im Reiter Jahr: Monate und Kunden.",
                "**Timesheet als PDF** – Tätigkeitsnachweis für Kunden, wahlweise nur abrechenbar, mit Notizen, Tags und Tagessummen.",
            ]),
            .paragraph("Zu finden unter **Berichte › Exportieren**, im Menü **Ablage** oder in der Befehlspalette (`csv`)."),
            .steps("Aus Toggl umziehen", [
                "In Toggl: **Reports › Detailed** wählen, Zeitraum einstellen, **Export › CSV**.",
                "In Takt: **Ablage › Toggl importieren …** (oder Berichte › Toggl importieren …).",
                "Datei wählen, Vorschau prüfen und jedem Toggl-Projekt ein Takt-Projekt zuordnen (oder neu anlegen lassen).",
                "**Importieren** – doppelte Einträge überspringt Takt, ein zweiter Import schadet also nicht.",
            ]),
            .link("Berichte öffnen", .section(.reports)),
            .link("Timesheet als PDF erstellen", .action(.exportTimesheetPDF)),
        ]
    )

    static let calendar = HelpTopic(
        id: "calendar",
        title: "Kalender",
        icon: "calendar",
        summary: "Termine neben deiner Zeit sehen, als Einträge übernehmen und Zeiten spiegeln.",
        keywords: ["termine", "eventkit", "google", "icloud", "exchange", "spiegeln", "regeln", "meeting"],
        destination: .settings("calendar"),
        blocks: [
            .steps("Zugriff erlauben", [
                "**Einstellungen › Kalender** öffnen.",
                "**Zugriff erlauben** klicken und in der Abfrage von macOS bestätigen.",
                "**Termine in „Heute“ anzeigen** ist danach eingeschaltet.",
            ]),
            .paragraph("Abgelehnt? Dann über **Systemeinstellungen › Datenschutz & Sicherheit › Kalender** freigeben – der Knopf in den Einstellungen führt direkt dorthin."),
            .heading("Termine in „Heute“"),
            .bullets([
                "Termine erscheinen als schraffierte Spur über der Tagesleiste und als Liste „Termine heute“.",
                "**Als Eintrag** übernimmt einen Termin: gleiche Zeit, Titel als Notiz, Tag „Meeting“.",
                "**✓ erfasst** heißt: Es gibt schon einen Eintrag mit genau dieser Zeit.",
                "Läuft ein Termin, während der Timer auf einem anderen Projekt steht, zeigt Takt einen Hinweis mit „Wechseln zu …“.",
            ]),
            .heading("Regeln: Termin → Projekt"),
            .paragraph("Damit Takt weiß, welches Projekt zu einem Termin gehört: nach **Kalendername**, **Titel enthält** oder **Teilnehmer-Domain** (z. B. `@acme.de` – passt auch zu `mail.acme.de`). Die erste passende Regel gewinnt; die Reihenfolge änderst du durch Ziehen."),
            .heading("Zeiten in einen Kalender spiegeln"),
            .paragraph("Auf Wunsch trägt Takt jeden Eintrag als Ereignis in einen eigenen Kalender **„Takt“** ein – praktisch, um die Woche im Kalender zu sehen. Takt verändert nur Ereignisse in diesem Kalender, nie andere. Kurze Einträge (Standard unter 5 Minuten) lässt es weg."),
            .steps("Google-Konto einrichten", [
                "**Systemeinstellungen › Internetaccounts › Account hinzufügen … › Google** wählen.",
                "Anmelden und bei den Diensten **Kalender** einschalten.",
                "In Takt: **Einstellungen › Kalender › Zeiten spiegeln**, als Quelle das Google-Konto wählen.",
                "Meldet Takt, dass dort kein Kalender angelegt werden kann: im Browser unter calendar.google.com einen Kalender „Takt“ anlegen und die Quelle in Takt erneut wählen.",
            ]),
            .link("Einstellungen › Kalender öffnen", .settings("calendar")),
        ]
    )

    static let activity = HelpTopic(
        id: "activity",
        title: "Aktivität",
        icon: "sparkles",
        summary: "Takt bemerkt, woran du arbeitest, und fragt, wenn der Timer nicht passt.",
        keywords: ["erkennung", "apps", "fenster", "repository", "git", "regeln", "vorschläge", "automatisch starten", "datenschutz", "bedienungshilfen"],
        destination: .settings("activity"),
        blocks: [
            .paragraph("Die Aktivitäts-Erkennung ist **aus**, bis du sie einschaltest. Dann schaut Takt alle 15 Sekunden, welche App vorne ist, und ordnet das einem Projekt zu."),
            .heading("Was erkannt wird"),
            .bullets([
                "**App:** welches Programm vorne ist (z. B. Xcode, Safari).",
                "**Fenstertitel:** nur mit der Freigabe **Bedienungshilfen**.",
                "**Git-Repository:** aus Dokument oder Titel, z. B. ein Ordner unter `~/dev`, `~/Developer`, `~/Projects` oder `~/code`.",
            ]),
            .heading("Was dann passiert"),
            .bullets([
                "Arbeitest du 10 Minuten (einstellbar) überwiegend an einem anderen Projekt als dem laufenden: „Passt der Timer?“ mit **Wechseln**.",
                "Läuft kein Timer: „Timer starten?“. Mit **Automatisch starten** startet Takt ihn gleich selbst.",
                "**Ignorieren** lässt dieselbe Frage zwei Stunden ruhen.",
            ]),
            .steps("Regeln anlegen", [
                "**Einstellungen › Aktivität** öffnen.",
                "Unter **Regeln** auf **+** klicken: Art wählen (App, Fenstertitel enthält oder Repo-Pfad), Muster und Projekt.",
                "Oder unter **Zuletzt erkannt** bei einer Zeile **Regel daraus** wählen.",
            ]),
            .paragraph("Ohne Regel rät Takt über den Ordnernamen: Heißt das Repository wie ein Projekt (z. B. `eventbuster-app` ↔ „EventBuster“), passt es."),
            .heading("Datenschutz"),
            .paragraph("Alles bleibt **auf diesem Mac**. Takt lädt nichts hoch. Erkannte Abschnitte werden nach 30 Tagen gelöscht. Ausschalten beendet die Beobachtung sofort. Passwortfelder und Inhalte von Fenstern liest Takt nicht – nur App, Titel und Ordner."),
            .link("Freigabe Bedienungshilfen prüfen", .helpTopic("permissions")),
            .link("Einstellungen › Aktivität öffnen", .settings("activity")),
        ]
    )

    static let notifications = HelpTopic(
        id: "notifications",
        title: "Mitteilungen & Ruhezeiten",
        icon: "bell.badge",
        summary: "Welche Mitteilungen es gibt und wie du sie zur richtigen Zeit bekommst.",
        keywords: ["benachrichtigungen", "hinweise", "ruhezeit", "wochenende", "nicht stören", "banner", "test"],
        destination: .settings("notifications"),
        blocks: [
            .paragraph("Unter **Einstellungen › Mitteilungen** stehen alle Arten an einem Ort, jede mit eigenem Schalter:"),
            .bullets([
                "**Pausenerinnerung** – nach langer Arbeit am Stück.",
                "**Pomodoro** – Pause beginnt, Pause vorbei (mit Ton, abschaltbar).",
                "**Leerlauf** – wenn Takt im Hintergrund ist und du zurückkommst.",
                "**Vergessener Timer** – nach vielen Stunden.",
                "**Budget** – bei 80 % und 100 % des Stundenbudgets.",
                "**Aktivität** – „Passt der Timer?“.",
                "**Geplanter Block** – zum Beginn, falls nichts läuft.",
                "**Termin-Hinweis** – nur in der App, keine Systemmitteilung.",
            ]),
            .heading("Ruhezeiten"),
            .paragraph("Zwischen zwei Uhrzeiten (Standard 18:00–08:00) und auf Wunsch am ganzen Wochenende bleibt Takt still. Ausnahme: der **vergessene Timer** meldet sich trotzdem, damit keine Nacht durchläuft."),
            .steps("Keine Mitteilungen?", [
                "**Einstellungen › Mitteilungen** öffnen und den Status oben prüfen.",
                "Steht dort „verweigert“: **In Systemeinstellungen öffnen** › Takt › Mitteilungen erlauben, Stil **Banner**.",
                "Den Fokus-Modus des Macs prüfen (Kontrollzentrum › Fokus) – „Nicht stören“ hält Mitteilungen zurück.",
                "**Testmitteilung senden** – kommt sie an, ist alles eingerichtet.",
            ]),
            .link("Einstellungen › Mitteilungen öffnen", .settings("notifications")),
        ]
    )

    static let permissions = HelpTopic(
        id: "permissions",
        title: "Freigaben",
        icon: "lock.shield",
        summary: "Die vier Erlaubnisse, nach denen macOS fragt – Status und Knopf an einem Ort.",
        keywords: ["berechtigung", "erlaubnis", "datenschutz", "automation", "bedienungshilfen", "accessibility", "kalender", "mitteilungen", "privacy"],
        blocks: [
            .paragraph("macOS fragt für bestimmte Dinge um Erlaubnis. **Alle Freigaben sind freiwillig:** Takt funktioniert ohne – es fehlt nur die jeweilige Funktion."),
            .live(.permissions),
            .note("Hast du einmal abgelehnt, fragt macOS nicht von selbst noch einmal. Dann über **Systemeinstellungen …** freigeben: Datenschutz & Sicherheit › (Automation, Kalender oder Bedienungshilfen) › Takt einschalten."),
            .tip("Nach dem Freigeben in den Systemeinstellungen einfach zu Takt zurückkehren – der Status aktualisiert sich von selbst."),
        ]
    )

    static let data = HelpTopic(
        id: "data",
        title: "Daten & Sicherung",
        icon: "externaldrive",
        summary: "Wo deine Daten liegen, wie Takt sie sichert und wie du sie mitnimmst.",
        keywords: ["datenbank", "sqlite", "backup", "sicherung", "wiederherstellen", "export", "time machine", "speicherort"],
        destination: .revealDatabase,
        blocks: [
            .paragraph("Alle Zeiten, Projekte und Regeln liegen in **einer Datei auf deinem Mac**. Kein Konto, keine Cloud. App und Widget teilen sich diese Datei."),
            .live(.dataLocation),
            .heading("Automatische Sicherungen"),
            .paragraph("Bevor Takt das Datenbankformat bei einem Update erweitert, legt es eine Kopie daneben an: `takt.sqlite.bak-v1`, `takt.sqlite.bak-v2` und so weiter. Takt löscht dabei nie Daten."),
            .steps("Sicherung zurückholen", [
                "Takt beenden – auch über die Menüleiste: **Beenden**.",
                "Im Ordner die aktuelle `takt.sqlite` samt `takt.sqlite-wal` und `takt.sqlite-shm` an einen anderen Ort verschieben.",
                "Die gewünschte Sicherung (z. B. `takt.sqlite.bak-v4`) kopieren und die Kopie in `takt.sqlite` umbenennen.",
                "Takt wieder starten.",
            ]),
            .tip("Time Machine sichert den Ordner automatisch mit. Für einen Umzug auf einen neuen Mac genügt es, die Datei `takt.sqlite` mitzunehmen (bei beendetem Takt)."),
            .heading("Daten mitnehmen"),
            .paragraph("Für Excel, Steuerberatung oder Kunden: **Ablage › Einträge als CSV exportieren …**, **Zusammenfassung …** oder **Timesheet als PDF …**. Einstellungen liegen nicht in der Datenbank, sondern in den macOS-Einstellungen von Takt."),
            .link("Datenbank im Finder zeigen", .revealDatabase),
            .link("Einträge als CSV exportieren", .action(.exportEntriesCSV)),
        ]
    )
}
