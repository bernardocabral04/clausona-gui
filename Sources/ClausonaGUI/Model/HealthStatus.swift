public enum HealthStatus: Equatable, Sendable {
    case healthy
    case issues([String])
    case unknown
}
