import SwiftUI
import TaktCore

/// Inhalt der Szene `Window(id: "help")`: verbindet `HelpWindow` mit Navigator, Einstellungen,
/// Menüleiste (Schnelleingabe, Hauptfenster) und den Freigaben.
struct HelpScene: View {
    @Environment(AppNavigator.self) private var navigator
    @Environment(AppSettings.self) private var settings
    @Environment(MenuBarController.self) private var menuBar
    @Environment(CalendarService.self) private var calendarService: CalendarService?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @State private var permissions: PermissionCenter?

    var body: some View {
        HelpWindow(
            center: HelpCenter.shared,
            context: HelpContext.current(settings),
            perform: { router.perform($0) },
            live: live
        )
        .registerHelpWindowOpener()
        .onAppear {
            if permissions == nil { permissions = PermissionCenter(calendarService: calendarService) }
        }
    }

    private var router: AppRouter {
        AppRouter(navigator: navigator, menuBar: menuBar, openWindow: openWindow, openSettings: openSettings)
    }

    private func live(_ kind: HelpBlock.Live) -> AnyView {
        switch kind {
        case .permissions:
            if let permissions {
                return AnyView(PermissionList(center: permissions))
            }
            return AnyView(ProgressView().controlSize(.small))
        case .dataLocation:
            return AnyView(HelpDataLocation(databaseURL: AppDatabase.defaultURL()))
        }
    }
}

extension HelpContext {
    /// Eingestellte globale Kurzbefehle (ausgeschaltet: „aus“).
    @MainActor
    static func current(_ settings: AppSettings) -> HelpContext {
        let toggle = KeyCombo(keyCode: settings.globalShortcutKeyCode,
                              modifiers: NSEvent.ModifierFlags(rawValue: settings.globalShortcutModifiers)).display
        let quick = KeyCombo(keyCode: settings.quickEntryHotKeyKeyCode,
                             modifiers: NSEvent.ModifierFlags(rawValue: settings.quickEntryHotKeyModifiers)).display
        return HelpContext(
            toggleShortcut: settings.globalShortcutEnabled ? toggle : "\(toggle) (aus)",
            quickEntryShortcut: settings.quickEntryHotKeyEnabled ? quick : "\(quick) (aus)"
        )
    }
}
