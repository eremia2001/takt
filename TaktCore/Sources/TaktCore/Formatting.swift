import Foundation

public enum DurationFormat {
    /// `h:mm`, abgerundet auf ganze Minuten: „0:00“, „1:05“, „12:30“.
    /// Negative oder ungültige Werte ergeben „0:00“.
    public static func hourMinute(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval > 0 else { return "0:00" }
        let totalMinutes = Int(interval / 60)  // Int(...) schneidet ab = abrunden bei positiven Werten
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes < 10 ? "\(hours):0\(minutes)" : "\(hours):\(minutes)"
    }
}
