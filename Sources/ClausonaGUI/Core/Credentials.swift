import CryptoKit
import Foundation

public enum Credentials {
    public struct Token: Equatable, Sendable {
        public let accessToken: String
        public let expiresAt: Date

        public init(accessToken: String, expiresAt: Date) {
            self.accessToken = accessToken
            self.expiresAt = expiresAt
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
            var expiresAt: Double?
        }
        struct RawBlob: Decodable {
            var claudeAiOauth: RawOauth?
        }
        guard let raw = try? JSONDecoder().decode(RawBlob.self, from: data),
              let accessToken = raw.claudeAiOauth?.accessToken, !accessToken.isEmpty,
              let expiresMS = raw.claudeAiOauth?.expiresAt, expiresMS > 0
        else { return nil }
        return Token(accessToken: accessToken, expiresAt: Date(timeIntervalSince1970: expiresMS / 1000))
    }

    public static func freshest(_ tokens: [Token]) -> Token? {
        tokens.max { $0.expiresAt < $1.expiresAt }
    }
}
