import Foundation

/// Uhrzeiten immer als `HH:mm` (24 Stunden), unabhängig von der Systemeinstellung.
enum ClockFormat {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func time(_ date: Date) -> String {
        formatter.string(from: date)
    }
}
