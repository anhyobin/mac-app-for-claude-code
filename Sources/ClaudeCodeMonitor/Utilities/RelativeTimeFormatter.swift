import Foundation

enum RelativeTimeFormatter {
    static func string(from interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        guard totalSeconds >= 0 else { return "0m" }

        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60

        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        } else if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        } else {
            return "\(max(minutes, 1))m"
        }
    }
}
