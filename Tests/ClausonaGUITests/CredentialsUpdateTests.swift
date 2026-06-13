import XCTest
@testable import ClausonaGUI

final class CredentialsUpdateTests: XCTestCase {
    func testParseCapturesRefreshToken() {
        let blob = #"{ "claudeAiOauth": { "accessToken": "at", "refreshToken": "rt", "expiresAt": 5000 } }"#
        let token = Credentials.parse(Data(blob.utf8))
        XCTAssertEqual(token?.refreshToken, "rt")
        XCTAssertEqual(Credentials.parse(Data(#"{ "claudeAiOauth": { "accessToken": "at", "expiresAt": 5000 } }"#.utf8))?.refreshToken, nil)
    }

    func testUpdatedBlobPreservesUnknownFieldsAndUpdatesTokens() throws {
        let original = """
        { "claudeAiOauth": { "accessToken": "old-at", "refreshToken": "old-rt", "expiresAt": 1000,
                             "scopes": ["user:inference"], "subscriptionType": "max",
                             "rateLimitTier": "default_claude_max_20x", "futureField": 42 },
          "otherTopLevel": true }
        """
        let refreshed = TokenRefresher.RefreshedToken(
            accessToken: "new-at", refreshToken: "new-rt",
            expiresAt: Date(timeIntervalSince1970: 9999))
        let updated = try XCTUnwrap(Credentials.updatedBlob(original: Data(original.utf8), with: refreshed))

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: updated) as? [String: Any])
        XCTAssertEqual(json["otherTopLevel"] as? Bool, true)
        let oauth = try XCTUnwrap(json["claudeAiOauth"] as? [String: Any])
        XCTAssertEqual(oauth["accessToken"] as? String, "new-at")
        XCTAssertEqual(oauth["refreshToken"] as? String, "new-rt")
        XCTAssertEqual(oauth["expiresAt"] as? Int, 9_999_000)   // integer ms epoch, like Claude Code writes
        XCTAssertEqual(oauth["scopes"] as? [String], ["user:inference"])
        XCTAssertEqual(oauth["subscriptionType"] as? String, "max")
        XCTAssertEqual(oauth["rateLimitTier"] as? String, "default_claude_max_20x")
        XCTAssertEqual(oauth["futureField"] as? Int, 42)

        // and the result must re-parse as valid credentials
        let token = Credentials.parse(updated)
        XCTAssertEqual(token?.accessToken, "new-at")
        XCTAssertEqual(token?.expiresAt, Date(timeIntervalSince1970: 9999))
    }

    func testUpdatedBlobKeepsOldRefreshTokenWhenNoneReturned() throws {
        let original = #"{ "claudeAiOauth": { "accessToken": "old", "refreshToken": "keep-me", "expiresAt": 1 } }"#
        let refreshed = TokenRefresher.RefreshedToken(accessToken: "new", refreshToken: nil,
                                                      expiresAt: Date(timeIntervalSince1970: 2))
        let updated = try XCTUnwrap(Credentials.updatedBlob(original: Data(original.utf8), with: refreshed))
        let token = Credentials.parse(updated)
        XCTAssertEqual(token?.refreshToken, "keep-me")
    }

    func testUpdatedBlobRejectsGarbage() {
        let refreshed = TokenRefresher.RefreshedToken(accessToken: "a", refreshToken: nil, expiresAt: Date())
        XCTAssertNil(Credentials.updatedBlob(original: Data("nope".utf8), with: refreshed))
    }
}
