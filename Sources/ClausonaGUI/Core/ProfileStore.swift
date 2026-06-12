import Foundation

/// Locates and loads $CLAUSONA_HOME/profiles.json (default ~/.clausona).
public struct ProfileStore: Sendable {
    public let profilesPath: String

    public init(environment: [String: String] = ProcessInfo.processInfo.environment,
                home: String = NSHomeDirectory()) {
        let base = environment["CLAUSONA_HOME"] ?? home + "/.clausona"
        profilesPath = base + "/profiles.json"
    }

    /// nil → clausona is not set up (file missing or unparseable).
    public func load() -> ProfilesFile? {
        guard let data = FileManager.default.contents(atPath: profilesPath) else { return nil }
        return try? ProfilesFile.decode(data)
    }
}
