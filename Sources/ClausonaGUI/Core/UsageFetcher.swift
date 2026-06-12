import Foundation

public enum UsageError: Error, Equatable, Sendable {
    case http(Int)
    case network(String)
    case malformed

    public var message: String {
        switch self {
        case .http(let code): "HTTP \(code)"
        case .network: "network error"
        case .malformed: "unexpected response"
        }
    }
}

public struct UsageFetcher: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public var transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.transport = transport
    }

    public static let live = UsageFetcher { try await URLSession.shared.data(for: $0) }

    public func fetch(token: String) async -> Result<UsageReport, UsageError> {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        do {
            let (data, response) = try await transport(request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { return .failure(.http(status)) }
            guard let report = try? UsageReport.decode(data) else { return .failure(.malformed) }
            return .success(report)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }
}
