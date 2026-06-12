public struct Profile: Equatable, Sendable {
    public let name: String
    public let configDir: String
    public let email: String?
    public let orgName: String?
    public let isPrimary: Bool

    public init(name: String, configDir: String, email: String?, orgName: String?, isPrimary: Bool) {
        self.name = name
        self.configDir = configDir
        self.email = email
        self.orgName = orgName
        self.isPrimary = isPrimary
    }
}
