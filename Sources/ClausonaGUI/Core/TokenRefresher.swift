import Foundation

/// Silently renews an expired Claude Code access token with its refresh token —
/// the same grant Claude Code itself performs when a session opens. Endpoint and
/// client id verified against the installed Claude Code binary (v2.1.177).
public struct TokenRefresher: Sendable {
    public static let endpoint = URL(string: "https://platform.claude.com/v1/oauth/token")!
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    public struct RefreshedToken: Equatable, Sendable {
        public let accessToken: String
        public let refreshToken: String?
        public let expiresAt: Date

        public init(accessToken: String, refreshToken: String?, expiresAt: Date) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.expiresAt = expiresAt
        }
    }

    public struct RefreshError: Error, Equatable, Sendable {
        public let message: String
    }

    public var transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    public var now: @Sendable () -> Date

    public init(transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse),
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.now = now
    }

    public static let live = TokenRefresher(transport: { try await URLSession.shared.data(for: $0) })

    public func refresh(refreshToken: String) async -> Result<RefreshedToken, RefreshError> {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
        ])

        struct RawResponse: Decodable {
            var access_token: String
            var refresh_token: String?
            var expires_in: Double
        }

        do {
            let (data, response) = try await transport(request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { return .failure(RefreshError(message: "HTTP \(status)")) }
            guard let raw = try? JSONDecoder().decode(RawResponse.self, from: data) else {
                return .failure(RefreshError(message: "unexpected response"))
            }
            return .success(RefreshedToken(accessToken: raw.access_token,
                                           refreshToken: raw.refresh_token,
                                           expiresAt: now().addingTimeInterval(raw.expires_in)))
        } catch {
            return .failure(RefreshError(message: error.localizedDescription))
        }
    }
}
