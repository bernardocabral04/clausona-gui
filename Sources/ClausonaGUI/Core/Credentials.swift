import CryptoKit
import Foundation

public enum Credentials {
    public struct Token: Equatable, Sendable {
        public let accessToken: String
        public let expiresAt: Date
        public let refreshToken: String?

        public init(accessToken: String, expiresAt: Date, refreshToken: String? = nil) {
            self.accessToken = accessToken
            self.expiresAt = expiresAt
            self.refreshToken = refreshToken
        }
    }

    /// "Claude Code-credentials-<first 8 hex of sha256(configDir)>" — same storage Claude Code uses.
    public static func serviceName(forConfigDir dir: String) -> String {
        let digest = SHA256.hash(data: Data(dir.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "Claude Code-credentials-" + hex.prefix(8)
    }

    /// Requires a non-empty token AND a positive expiry, matching clausona-limits
    /// (a token without expiresAt is never selected there either).
    public static func parse(_ data: Data) -> Token? {
        struct RawOauth: Decodable {
            var accessToken: String?
            var refreshToken: String?
            var expiresAt: Double?
        }
        struct RawBlob: Decodable {
            var claudeAiOauth: RawOauth?
        }
        guard let raw = try? JSONDecoder().decode(RawBlob.self, from: data),
              let accessToken = raw.claudeAiOauth?.accessToken, !accessToken.isEmpty,
              let expiresMS = raw.claudeAiOauth?.expiresAt, expiresMS > 0
        else { return nil }
        return Token(accessToken: accessToken,
                     expiresAt: Date(timeIntervalSince1970: expiresMS / 1000),
                     refreshToken: raw.claudeAiOauth?.refreshToken)
    }

    public static func freshest(_ tokens: [Token]) -> Token? {
        tokens.max { $0.expiresAt < $1.expiresAt }
    }

    /// Rebuilds a credentials blob after a token refresh, preserving every field
    /// we don't understand (scopes, subscriptionType, rateLimitTier, future keys)
    /// so Claude Code can keep reading its own data. Returns nil rather than risk
    /// writing a malformed blob.
    public static func updatedBlob(original: Data, with refreshed: TokenRefresher.RefreshedToken) -> Data? {
        guard var root = (try? JSONSerialization.jsonObject(with: original)) as? [String: Any],
              var oauth = root["claudeAiOauth"] as? [String: Any] else { return nil }
        oauth["accessToken"] = refreshed.accessToken
        if let newRefreshToken = refreshed.refreshToken {
            oauth["refreshToken"] = newRefreshToken
        }
        oauth["expiresAt"] = Int((refreshed.expiresAt.timeIntervalSince1970 * 1000).rounded())   // integer ms, like Claude Code writes
        root["claudeAiOauth"] = oauth
        return try? JSONSerialization.data(withJSONObject: root)
    }
}
