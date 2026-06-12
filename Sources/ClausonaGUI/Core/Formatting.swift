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

    private nonisolated(unsafe) static let costFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")   // deterministic separators, matching the CLI
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private nonisolated(unsafe) static let tokensFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    public static func cost(_ value: Double) -> String {
        "$" + (costFormatter.string(from: value as NSNumber) ?? String(format: "%.2f", value))
    }

    public static func tokens(_ value: Int) -> String {
        tokensFormatter.string(from: value as NSNumber) ?? String(value)
    }
}

public enum UsageSeverity: Equatable, Sendable {
    case normal, elevated, critical

    public init(percent: Int) {
        self = percent >= 90 ? .critical : percent >= 70 ? .elevated : .normal
    }
}
