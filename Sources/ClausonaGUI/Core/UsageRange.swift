import Foundation

/// Time ranges for the dashboard. "This week" mirrors clausona's Monday-start
/// week exactly (success criterion: totals match `clausona list`).
public enum UsageRange: String, CaseIterable, Identifiable, Sendable {
    case thisWeek = "This week"
    case lastWeek = "Last week"
    case thisMonth = "This month"
    case allTime = "All time"

    public var id: String { rawValue }

    /// nil = all time (no filtering). `end` is exclusive; open-ended ranges use distantFuture.
    public func interval(now: Date, calendar: Calendar) -> DateInterval? {
        let todayStart = calendar.startOfDay(for: now)
        switch self {
        case .allTime:
            return nil
        case .thisWeek:
            return DateInterval(start: monday(of: todayStart, calendar: calendar), end: .distantFuture)
        case .lastWeek:
            let thisMonday = monday(of: todayStart, calendar: calendar)
            let lastMonday = calendar.date(byAdding: .day, value: -7, to: thisMonday)!
            return DateInterval(start: lastMonday, end: thisMonday)
        case .thisMonth:
            let comps = calendar.dateComponents([.year, .month], from: todayStart)
            return DateInterval(start: calendar.date(from: comps)!, end: .distantFuture)
        }
    }

    /// Port of clausona's cutoffForPeriod week branch: weekday 1=Sunday → back 6 days,
    /// otherwise back (weekday - 2) days.
    private func monday(of dayStart: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: dayStart)
        let delta = weekday == 1 ? 6 : weekday - 2
        return calendar.date(byAdding: .day, value: -delta, to: dayStart)!
    }
}
