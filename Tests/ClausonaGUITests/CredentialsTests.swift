import XCTest
@testable import ClausonaGUI

final class CredentialsTests: XCTestCase {
    func testServiceName() {
        XCTAssertEqual(Credentials.serviceName(forConfigDir: "/Users/test/.claude"),
                       "Claude Code-credentials-462977e4")
        XCTAssertEqual(Credentials.serviceName(forConfigDir: "/Users/bernardo/.claude"),
                       "Claude Code-credentials-756a26b6")
    }

    func testParseValidBlob() {
        let blob = #"{ "claudeAiOauth": { "accessToken": "tok-abc", "expiresAt": 1781310599000, "scopes": ["x"] } }"#
        let token = Credentials.parse(Data(blob.utf8))
        XCTAssertEqual(token?.accessToken, "tok-abc")
        XCTAssertEqual(token?.expiresAt, Date(timeIntervalSince1970: 1_781_310_599))
    }

    func testParseRejectsEmptyTokenMissingExpiryAndGarbage() {
        XCTAssertNil(Credentials.parse(Data(#"{ "claudeAiOauth": { "accessToken": "", "expiresAt": 5 } }"#.utf8)))
        XCTAssertNil(Credentials.parse(Data(#"{ "claudeAiOauth": { "accessToken": "tok" } }"#.utf8)))
        XCTAssertNil(Credentials.parse(Data("nope".utf8)))
        XCTAssertNil(Credentials.parse(Data("{}".utf8)))
    }

    func testFreshestPicksLatestExpiry() {
        let old = Credentials.Token(accessToken: "old", expiresAt: Date(timeIntervalSince1970: 100))
        let new = Credentials.Token(accessToken: "new", expiresAt: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(Credentials.freshest([old, new])?.accessToken, "new")
        XCTAssertEqual(Credentials.freshest([new, old])?.accessToken, "new")
        XCTAssertNil(Credentials.freshest([]))
    }
}
