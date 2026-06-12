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

public enum CredentialStatus: Equatable, Sendable {
    case unknown            // not checked yet
    case valid(until: Date)
    case expired
    case missing
}

public struct ProfileSnapshot: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let email: String?
    public var isActive: Bool
    public var usage: UsageState
    public var health: HealthStatus
    public var isRepairing: Bool
    public var credential: CredentialStatus

    public init(name: String, email: String?, isActive: Bool,
                usage: UsageState, health: HealthStatus, isRepairing: Bool,
                credential: CredentialStatus = .unknown) {
        self.name = name
        self.email = email
        self.isActive = isActive
        self.usage = usage
        self.health = health
        self.isRepairing = isRepairing
        self.credential = credential
    }
}
