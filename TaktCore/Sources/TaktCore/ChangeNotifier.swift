import CoreFoundation
import Foundation

/// Prozessübergreifender Anstoß zwischen App und Widget-Extension per Darwin-Notification.
/// Transportiert keine Daten – Empfänger lesen danach selbst aus der Datenbank.
public enum ChangeNotifier {
    public static let notificationName = "dev.eremiya.takt.changed"

    /// Meldet allen Prozessen (auch dem eigenen), dass sich Daten geändert haben.
    public static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName as CFString),
            nil, nil, true
        )
    }

    /// Ruft `handler` bei jeder Änderungsmeldung auf dem Main-Thread auf, solange das
    /// zurückgegebene Token lebt.
    public static func observe(_ handler: @escaping @Sendable () -> Void) -> ChangeObservation {
        ChangeObservation(handler: handler)
    }
}

/// Token einer Beobachtung; beim Freigeben wird der Observer entfernt.
public final class ChangeObservation: @unchecked Sendable {
    /// Vom C-Callback erreichbares Objekt mit dem Handler.
    private final class Box {
        let handler: @Sendable () -> Void
        init(_ handler: @escaping @Sendable () -> Void) { self.handler = handler }
    }

    private let box: Unmanaged<Box>

    fileprivate init(handler: @escaping @Sendable () -> Void) {
        box = Unmanaged.passRetained(Box(handler))
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            box.toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let handler = Unmanaged<Box>.fromOpaque(observer).takeUnretainedValue().handler
                if Thread.isMainThread {
                    handler()
                } else {
                    DispatchQueue.main.async { handler() }
                }
            },
            ChangeNotifier.notificationName as CFString,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        let box = self.box
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            box.toOpaque(),
            CFNotificationName(ChangeNotifier.notificationName as CFString),
            nil
        )
        // Erst auf dem Main-Thread freigeben, damit ein gerade zugestellter Callback die Box
        // nicht nach der Freigabe anfasst.
        DispatchQueue.main.async { box.release() }
    }
}
