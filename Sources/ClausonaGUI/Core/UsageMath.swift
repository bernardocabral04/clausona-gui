import Foundation

public enum UsageMath {
    /// interval end is exclusive (a record exactly at .end belongs to the next bucket).
    public static func totals(_ records: [UsageRecord], in interval: DateInterval?) -> ProfileTotals {
        records.reduce(into: .zero) { acc, record in
            guard contains(interval, record.ts) else { return }
            acc.cost += record.cost
            acc.inputTokens += record.inputTokens
            acc.outputTokens += record.outputTokens
        }
    }

    public static func totalsByProfile(_ byProfile: [String: [UsageRecord]],
                                       in interval: DateInterval?) -> [String: ProfileTotals] {
        byProfile.mapValues { totals($0, in: interval) }
    }

    /// One entry per (local day, profile) with non-zero cost, sorted by day then profile —
    /// ready for a stacked BarMark chart.
    public static func dailyCosts(_ byProfile: [String: [UsageRecord]],
                                  in interval: DateInterval?,
                                  calendar: Calendar) -> [DailyProfileCost] {
        var buckets: [Date: [String: Double]] = [:]
        for (profile, records) in byProfile {
            for record in records where contains(interval, record.ts) {
                let day = calendar.startOfDay(for: record.ts)
                buckets[day, default: [:]][profile, default: 0] += record.cost
            }
        }
        return buckets
            .flatMap { day, profiles in
                profiles.map { DailyProfileCost(day: day, profile: $0.key, cost: $0.value) }
            }
            .sorted { ($0.day, $0.profile) < ($1.day, $1.profile) }
    }

    private static func contains(_ interval: DateInterval?, _ date: Date) -> Bool {
        guard let interval else { return true }
        return date >= interval.start && date < interval.end
    }
}
