import Foundation

public enum Formatting {
    /// Port of clausona-limits' fmt_dur.
    public static func duration(seconds: Int) -> String {
        guard seconds >= 0 else { return "?" }
        let days = seconds / 86400
        let hours = seconds % 86400 / 3600
        let minutes = seconds % 3600 / 60
        if days > 0 { return "\(days)d\(hours)h" }
        if hours > 0 { return String(format: "%dh%02dm", hours, minutes) }
        return "\(minutes)m"
    }

    public static func updatedAgo(seconds: Int) -> String {
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}

public enum UsageSeverity: Equatable, Sendable {
    case normal, elevated, critical

    public init(percent: Int) {
        self = percent >= 90 ? .critical : percent >= 70 ? .elevated : .normal
    }
}
