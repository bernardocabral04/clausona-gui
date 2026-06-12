import XCTest
@testable import ClausonaGUI

final class UsageFetcherTests: XCTestCase {
    private static func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: UsageFetcher.endpoint, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    func testSuccessSendsAuthAndBetaHeaders() async {
        let body = #"{ "five_hour": { "utilization": 12.0, "resets_at": null } }"#
        nonisolated(unsafe) var captured: URLRequest?
        let fetcher = UsageFetcher { request in
            captured = request
            return (Data(body.utf8), Self.response(200))
        }
        let result = await fetcher.fetch(token: "tok-123")
        XCTAssertEqual(try? result.get().fiveHour?.utilization, 12)
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer tok-123")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(captured?.timeoutInterval, 15)
    }

    func testHTTPErrorMapped() async {
        let fetcher = UsageFetcher { _ in (Data(), Self.response(401)) }
        let result = await fetcher.fetch(token: "t")
        XCTAssertEqual(result, .failure(.http(401)))
        XCTAssertEqual(UsageError.http(401).message, "HTTP 401")
    }

    func testMalformedBody() async {
        let fetcher = UsageFetcher { _ in (Data("nope".utf8), Self.response(200)) }
        let result = await fetcher.fetch(token: "t")
        XCTAssertEqual(result, .failure(.malformed))
    }

    func testNetworkErrorMapped() async {
        struct Boom: Error {}
        let fetcher = UsageFetcher { _ in throw Boom() }
        guard case .failure(.network) = await fetcher.fetch(token: "t") else { return XCTFail("expected network error") }
    }
}
