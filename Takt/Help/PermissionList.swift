import SwiftUI

// Freigaben-Liste ohne Systemzugriffe (rein darstellend), damit Hilfe und Einführung im
// Render-Harness laufen. Status und Aktionen liefert `PermissionCenter`.

/// Die vier Systemfreigaben, die Takt nutzen kann – alle optional.
enum PermissionKind: String, CaseIterable, Identifiable {
    case notifications, automation, calendar, accessibility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notifications: "Mitteilungen"
        case .automation: "Automation (Musik)"
        case .calendar: "Kalender"
        case .accessibility: "Bedienungshilfen"
        }
    }

    var symbol: String {
        switch self {
        case .notifications: "bell.badge"
        case .automation: "music.note"
        case .calendar: "calendar"
        case .accessibility: "accessibility"
        }
    }

    /// Wofür Takt die Freigabe braucht – ein Satz.
    var purpose: String {
        switch self {
        case .notifications: "Pausenerinnerung, Pomodoro, Leerlauf, Budget und geplante Blöcke."
        case .automation: "Damit Takt Spotify bzw. Musik beim Start abspielen und beim Stopp pausieren darf."
        case .calendar: "Termine in „Heute“ zeigen und Zeiten in den Kalender „Takt“ eintragen."
        case .accessibility: "Fenstertitel für die Aktivitäts-Erkennung und die Medientaste für Musik im Browser."
        }
    }
}

/// Alle vier Freigaben untereinander (Hilfe › Freigaben, Einführung Seite 4). Rein darstellend.
struct PermissionList: View {
    var kinds: [PermissionKind] = PermissionKind.allCases
    let state: (PermissionKind) -> PermissionState
    let request: (PermissionKind) -> Void
    let openSettings: (PermissionKind) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = DesignTheme(scheme: scheme)
        VStack(spacing: 0) {
            ForEach(Array(kinds.enumerated()), id: \.element) { index, kind in
                if index > 0 { Divider().padding(.leading, 46) }
                PermissionRow(
                    symbol: kind.symbol,
                    title: kind.title,
                    state: state(kind),
                    purpose: kind.purpose,
                    request: { request(kind) },
                    openSettings: { openSettings(kind) }
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
    }
}
