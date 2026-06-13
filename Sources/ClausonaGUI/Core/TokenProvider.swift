import Foundation

public enum TokenResult: Equatable, Sendable {
    case ok(Credentials.Token)
    case missing
    case expired
}

/// Port of clausona-limits' token_for_dir, extended with silent refresh:
/// an expired access token with a stored refresh token is renewed in place
/// (the same grant Claude Code performs) and persisted back to the keychain.
/// Tokens stay in memory otherwise — never logged or rendered.
public struct TokenProvider: Sendable {
    public var readSecret: @Sendable (String) async -> Data?
    public var readCredentialsFile: @Sendable (String) -> Data?
    public var legacyDir: String
    public var now: @Sendable () -> Date
    /// nil disables silent refresh (tests for the pre-refresh behavior set this).
    public var refresh: (@Sendable (String) async -> Result<TokenRefresher.RefreshedToken, TokenRefresher.RefreshError>)?
    /// Persists an updated credentials blob; returns success. nil disables persistence.
    public var writeSecret: (@Sendable (String, Data) async -> Bool)?

    public init(readSecret: @escaping @Sendable (String) async -> Data?,
                readCredentialsFile: @escaping @Sendable (String) -> Data?,
                legacyDir: String,
                now: @escaping @Sendable () -> Date,
                refresh: (@Sendable (String) async -> Result<TokenRefresher.RefreshedToken, TokenRefresher.RefreshError>)? = nil,
                writeSecret: (@Sendable (String, Data) async -> Bool)? = nil) {
        self.readSecret = readSecret
        self.readCredentialsFile = readCredentialsFile
        self.legacyDir = legacyDir
        self.now = now
        self.refresh = refresh
        self.writeSecret = writeSecret
    }

    public func token(forConfigDir dir: String) async -> TokenResult {
        var services = [Credentials.serviceName(forConfigDir: dir)]
        if dir == legacyDir { services.append("Claude Code-credentials") }

        var candidates: [(token: Credentials.Token, blob: Data)] = []
        for service in services {
            if let blob = await readSecret(service), let token = Credentials.parse(blob) {
                candidates.append((token, blob))
            }
        }
        if let data = readCredentialsFile(dir), let token = Credentials.parse(data) {
            candidates.append((token, data))
        }
        guard let best = candidates.max(by: { $0.token.expiresAt < $1.token.expiresAt }) else {
            return .missing
        }
        if best.token.expiresAt > now() {
            return .ok(best.token)
        }
        return await refreshIfPossible(best, configDir: dir)
    }

    private func refreshIfPossible(_ stale: (token: Credentials.Token, blob: Data),
                                   configDir: String) async -> TokenResult {
        guard let refresh, let refreshToken = stale.token.refreshToken else { return .expired }
        guard case .success(let renewed) = await refresh(refreshToken) else { return .expired }

        // Persist so Claude Code (and our next launch) see the renewed pair.
        // A failed write is non-fatal: the fresh token still serves this cycle.
        if let writeSecret,
           let blob = Credentials.updatedBlob(original: stale.blob, with: renewed) {
            _ = await writeSecret(Credentials.serviceName(forConfigDir: configDir), blob)
        }
        return .ok(Credentials.Token(accessToken: renewed.accessToken,
                                     expiresAt: renewed.expiresAt,
                                     refreshToken: renewed.refreshToken ?? stale.token.refreshToken))
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
            now: { Date() },
            refresh: { await TokenRefresher.live.refresh(refreshToken: $0) },
            writeSecret: { service, blob in
                // Reuse the item's existing account attribute (falls back to the
                // current user, which is what Claude Code uses).
                var account = NSUserName()
                if let info = await Subprocess.run("/usr/bin/security",
                                                   ["find-generic-password", "-s", service]),
                   info.exitCode == 0,
                   let match = info.stdout.firstMatch(of: /"acct"<blob>="([^"]*)"/) {
                    account = String(match.1)
                }
                let result = await Subprocess.run("/usr/bin/security",
                                                  ["add-generic-password", "-U",
                                                   "-a", account,
                                                   "-s", service,
                                                   "-w", String(decoding: blob, as: UTF8.self)])
                return result?.exitCode == 0
            })
    }
}
