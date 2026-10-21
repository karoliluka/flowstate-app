import Foundation

extension TimeInterval {
    /// "42s", "14m", "1h", "2h 14m"
    var focusFormatted: String {
        let totalSeconds = Int(self)
        guard totalSeconds >= 60 else { return "\(totalSeconds)s" }
        let totalMinutes = totalSeconds / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }

    /// "1:02:09" or "02:09", for the live timer.
    var clockFormatted: String {
        let total = Int(self)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}
