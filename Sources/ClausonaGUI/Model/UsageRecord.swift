import Foundation

public struct UsageRecord: Equatable, Sendable {
    public let ts: Date
    public let cost: Double
    public let inputTokens: Int
    public let outputTokens: Int

    public init(ts: Date, cost: Double, inputTokens: Int, outputTokens: Int) {
        self.ts = ts
        self.cost = cost
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public struct ProfileTotals: Equatable, Sendable {
    public var cost: Double
    public var inputTokens: Int
    public var outputTokens: Int

    public static let zero = ProfileTotals(cost: 0, inputTokens: 0, outputTokens: 0)

    public init(cost: Double, inputTokens: Int, outputTokens: Int) {
        self.cost = cost
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public struct DailyProfileCost: Equatable, Sendable, Identifiable {
    public var id: String { "\(day.timeIntervalSince1970)-\(profile)" }
    public let day: Date
    public let profile: String
    public let cost: Double

    public init(day: Date, profile: String, cost: Double) {
        self.day = day
        self.profile = profile
        self.cost = cost
    }
}

/// Decodes ~/.clausona/usage.json. Tolerant per record: a malformed record is
/// skipped, never fatal (the file is owned by clausona; we only read it).
public enum UsageLog {
    public static func decode(_ data: Data) throws -> [String: [UsageRecord]] {
        // Lossy wrapper: a record that fails to decode becomes nil instead of
        // failing the whole array.
        struct Lossy: Decodable {
            let record: RawRecord?
            init(from decoder: Decoder) {
                record = try? RawRecord(from: decoder)
            }
        }
        struct RawRecord: Decodable {
            var ts: String
            var cost: Double
            var inputTokens: Int
            var outputTokens: Int
        }
        struct RawProfile: Decodable {
            var records: [Lossy]?
        }
        let raw = try JSONDecoder().decode([String: RawProfile].self, from: data)
        return raw.mapValues { profile in
            (profile.records ?? []).compactMap { lossy in
                guard let r = lossy.record, let ts = APIDate.parse(r.ts) else { return nil }
                return UsageRecord(ts: ts, cost: r.cost, inputTokens: r.inputTokens, outputTokens: r.outputTokens)
            }
        }
    }
}
