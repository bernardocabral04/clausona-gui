import XCTest
@testable import ClausonaGUI

final class TokenRefresherTests: XCTestCase {
    nonisolated static let now = Date(timeIntervalSince1970: 1_000_000)

    private static func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: TokenRefresher.endpoint, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    func testSendsStandardRefreshGrant() async throws {
        let body = #"{ "access_token": "new-at", "refresh_token": "new-rt", "expires_in": 28800 }"#
        nonisolated(unsafe) var captured: URLRequest?
        nonisolated(unsafe) var capturedBody: Data?
        let refresher = TokenRefresher(transport: { request in
            captured = request
            capturedBody = request.httpBody
            return (Data(body.utf8), Self.response(200))
        }, now: { Self.now })

        let result = try await refresher.refresh(refreshToken: "old-rt").get()
        XCTAssertEqual(result.accessToken, "new-at")
        XCTAssertEqual(result.refreshToken, "new-rt")
        XCTAssertEqual(result.expiresAt, Self.now.addingTimeInterval(28800))

        XCTAssertEqual(captured?.url, URL(string: "https://platform.claude.com/v1/oauth/token"))
        XCTAssertEqual(captured?.httpMethod, "POST")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let json = try JSONSerialization.jsonObject(with: capturedBody ?? Data()) as? [String: String]
        XCTAssertEqual(json?["grant_type"], "refresh_token")
        XCTAssertEqual(json?["refresh_token"], "old-rt")
        XCTAssertEqual(json?["client_id"], "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
    }

    func testMissingNewRefreshTokenIsAllowed() async throws {
        let body = #"{ "access_token": "new-at", "expires_in": 3600 }"#
        let refresher = TokenRefresher(transport: { _ in (Data(body.utf8), Self.response(200)) }, now: { Self.now })
        let result = try await refresher.refresh(refreshToken: "rt").get()
        XCTAssertEqual(result.accessToken, "new-at")
        XCTAssertNil(result.refreshToken)
    }

    func testHTTPErrorFails() async {
        let refresher = TokenRefresher(transport: { _ in (Data(#"{"error":"invalid_grant"}"#.utf8), Self.response(400)) },
                                       now: { Self.now })
        let result = await refresher.refresh(refreshToken: "rt")
        guard case .failure = result else { return XCTFail("expected failure") }
    }

    func testMalformedBodyFails() async {
        let refresher = TokenRefresher(transport: { _ in (Data("nope".utf8), Self.response(200)) }, now: { Self.now })
        let result = await refresher.refresh(refreshToken: "rt")
        guard case .failure = result else { return XCTFail("expected failure") }
    }
}
