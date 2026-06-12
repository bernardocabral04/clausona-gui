import Foundation

public enum UsageState: Equatable, Sendable {
    case loading
    case ok(UsageReport)
    case error(message: String, lastGood: UsageReport?)

    public var lastGoodReport: UsageReport? {
        switch self {
        case .loading: nil
        case .ok(let report): report
        case .error(_, let lastGood): lastGood
        }
    }
}

public struct ProfileSnapshot: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let email: String?
    public var isActive: Bool
    public var usage: UsageState
    public var health: HealthStatus
    public var isRepairing: Bool

    public init(name: String, email: String?, isActive: Bool,
                usage: UsageState, health: HealthStatus, isRepairing: Bool) {
        self.name = name
        self.email = email
        self.isActive = isActive
        self.usage = usage
        self.health = health
        self.isRepairing = isRepairing
    }
}
