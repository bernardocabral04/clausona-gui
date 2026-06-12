import Foundation

public enum TokenResult: Equatable, Sendable {
    case ok(Credentials.Token)
    case missing
    case expired
}

/// Port of clausona-limits' token_for_dir. Tokens stay in memory only —
/// never logged, written, or rendered.
public struct TokenProvider: Sendable {
    public var readSecret: @Sendable (String) async -> Data?
    public var readCredentialsFile: @Sendable (String) -> Data?
    public var legacyDir: String
    public var now: @Sendable () -> Date

    public init(readSecret: @escaping @Sendable (String) async -> Data?,
                readCredentialsFile: @escaping @Sendable (String) -> Data?,
                legacyDir: String,
                now: @escaping @Sendable () -> Date) {
        self.readSecret = readSecret
        self.readCredentialsFile = readCredentialsFile
        self.legacyDir = legacyDir
        self.now = now
    }

    public func token(forConfigDir dir: String) async -> TokenResult {
        var services = [Credentials.serviceName(forConfigDir: dir)]
        if dir == legacyDir { services.append("Claude Code-credentials") }

        var candidates: [Credentials.Token] = []
        for service in services {
            if let blob = await readSecret(service), let token = Credentials.parse(blob) {
                candidates.append(token)
            }
        }
        if let data = readCredentialsFile(dir), let token = Credentials.parse(data) {
            candidates.append(token)
        }
        guard let best = Credentials.freshest(candidates) else { return .missing }
        return best.expiresAt > now() ? .ok(best) : .expired
    }

    /// Live wiring: keychain via /usr/bin/security (existing ACL — no new prompts);
    /// file fallback only when .credentials.json is a real file, not clausona's
    /// symlink to the primary profile's credentials.
    public static func live(legacyDir: String = NSHomeDirectory() + "/.claude") -> TokenProvider {
        TokenProvider(
            readSecret: { service in
                guard let result = await Subprocess.run("/usr/bin/security",
                                                        ["find-generic-password", "-s", service, "-w"]),
                      result.exitCode == 0 else { return nil }
                return Data(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
            },
            readCredentialsFile: { dir in
                let path = dir + "/.credentials.json"
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                      attrs[.type] as? FileAttributeType == .typeRegular else { return nil }
                return FileManager.default.contents(atPath: path)
            },
            legacyDir: legacyDir,
            now: { Date() })
    }
}
