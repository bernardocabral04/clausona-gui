import Foundation
import Observation

/// Loads, watches, and aggregates ~/.clausona/usage.json for the dashboard.
/// The file is owned by clausona — strictly read-only here.
@MainActor @Observable
public final class UsageStore {
    public private(set) var recordsByProfile: [String: [UsageRecord]] = [:]
    public private(set) var loadFailed = false
    public var range: UsageRange = .thisWeek

    private let usagePath: String
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    @ObservationIgnored private var watcher: FileWatcher?

    public init(environment: [String: String] = ProcessInfo.processInfo.environment,
                home: String = NSHomeDirectory(),
                calendar: Calendar = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
        let base = environment["CLAUSONA_HOME"] ?? home + "/.clausona"
        usagePath = base + "/usage.json"
        self.calendar = calendar
        self.now = now
    }

    /// Initial load + live reload while sessions run.
    public func start() {
        reload()
        if watcher == nil {
            watcher = FileWatcher(path: usagePath) { [weak self] in self?.reload() }
            watcher?.start()
        }
    }

    public func reload() {
        guard let data = FileManager.default.contents(atPath: usagePath),
              let log = try? UsageLog.decode(data) else {
            recordsByProfile = [:]
            loadFailed = true
            return
        }
        recordsByProfile = log
        loadFailed = false
    }

    public var interval: DateInterval? {
        range.interval(now: now(), calendar: calendar)
    }

    public func totalsByProfile() -> [String: ProfileTotals] {
        UsageMath.totalsByProfile(recordsByProfile, in: interval)
    }

    public func grandTotalCost() -> Double {
        totalsByProfile().values.reduce(0) { $0 + $1.cost }
    }

    public func dailyCosts() -> [DailyProfileCost] {
        UsageMath.dailyCosts(recordsByProfile, in: interval, calendar: calendar)
    }
}
