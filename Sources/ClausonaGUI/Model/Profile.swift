import Foundation

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

public struct ProfilesFile: Equatable, Sendable {
    public let activeProfile: String?
    public let profiles: [Profile]   // sorted by name for stable display

    public init(activeProfile: String?, profiles: [Profile]) {
        self.activeProfile = activeProfile
        self.profiles = profiles
    }

    public static func decode(_ data: Data) throws -> ProfilesFile {
        struct RawProfile: Decodable {
            var configDir: String?
            var email: String?
            var orgName: String?
            var isPrimary: Bool?
        }
        struct RawFile: Decodable {
            var activeProfile: String?
            var profiles: [String: RawProfile]?
        }
        let raw = try JSONDecoder().decode(RawFile.self, from: data)
        let profiles = (raw.profiles ?? [:])
            .compactMap { name, p -> Profile? in
                guard let dir = p.configDir else { return nil }
                return Profile(name: name, configDir: dir, email: p.email,
                               orgName: p.orgName, isPrimary: p.isPrimary ?? false)
            }
            .sorted { $0.name < $1.name }
        return ProfilesFile(activeProfile: raw.activeProfile, profiles: profiles)
    }
}
