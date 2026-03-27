import Foundation

enum RelativeTimeFormatter {
    static func string(from date: Date, relativeTo now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86_400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if interval < 172_800 {
            return "yesterday"
        } else if interval < 604_800 {
            let days = Int(interval / 86_400)
            return "\(days)d ago"
        } else {
            let formatter = DateFormatter()
            formatter.locale = .autoupdatingCurrent
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}
