import Foundation

public struct UsageWindow: Equatable, Sendable {
    public let utilization: Int      // rounded percent
    public let resetsAt: Date?

    public init(utilization: Int, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

public struct UsageReport: Equatable, Sendable {
    public let fiveHour: UsageWindow?
    public let sevenDay: UsageWindow?

    public init(fiveHour: UsageWindow?, sevenDay: UsageWindow?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    public static func decode(_ data: Data) throws -> UsageReport {
        struct RawWindow: Decodable {
            var utilization: Double?
            var resets_at: String?
        }
        struct RawUsage: Decodable {
            var five_hour: RawWindow?
            var seven_day: RawWindow?
        }
        let raw = try JSONDecoder().decode(RawUsage.self, from: data)
        func window(_ w: RawWindow?) -> UsageWindow? {
            guard let w, let utilization = w.utilization else { return nil }
            return UsageWindow(utilization: Int(utilization.rounded()),
                               resetsAt: w.resets_at.flatMap(APIDate.parse))
        }
        return UsageReport(fiveHour: window(raw.five_hour), sevenDay: window(raw.seven_day))
    }
}

/// The usage endpoint emits 6-digit fractional seconds, which ISO8601DateFormatter
/// rejects — strip the fraction first (same as clausona-limits' jq `ep` helper).
public enum APIDate {
    public static func parse(_ string: String) -> Date? {
        let stripped = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: stripped)
    }
}
