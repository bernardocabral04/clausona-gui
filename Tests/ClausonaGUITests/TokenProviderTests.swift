import XCTest
@testable import ClausonaGUI

final class TokenProviderTests: XCTestCase {
    private func blob(token: String, expiresMS: Double) -> Data {
        Data(#"{ "claudeAiOauth": { "accessToken": "\#(token)", "expiresAt": \#(expiresMS) } }"#.utf8)
    }

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func provider(secrets: [String: Data], files: [String: Data] = [:]) -> TokenProvider {
        TokenProvider(
            readSecret: { secrets[$0] },
            readCredentialsFile: { files[$0] },
            legacyDir: "/Users/test/.claude",
            now: { [now] in now })
    }

    func testHashedServiceHit() async {
        let svc = Credentials.serviceName(forConfigDir: "/Users/test/.claude-work")
        let p = provider(secrets: [svc: blob(token: "tok-w", expiresMS: 2_000_000_000)])
        let result = await p.token(forConfigDir: "/Users/test/.claude-work")
        XCTAssertEqual(result, .ok(Credentials.Token(accessToken: "tok-w", expiresAt: Date(timeIntervalSince1970: 2_000_000))))
    }

    func testLegacyServiceOnlyForLegacyDir() async {
        let secrets = ["Claude Code-credentials": blob(token: "legacy", expiresMS: 2_000_000_000)]
        let hit = await provider(secrets: secrets).token(forConfigDir: "/Users/test/.claude")
        if case .ok(let token) = hit { XCTAssertEqual(token.accessToken, "legacy") } else { XCTFail("\(hit)") }
        let miss = await provider(secrets: secrets).token(forConfigDir: "/Users/test/.claude-work")
        XCTAssertEqual(miss, .missing)
    }

    func testFileFallbackBeatsStalerKeychain() async {
        let svc = Credentials.serviceName(forConfigDir: "/d")
        let p = provider(secrets: [svc: blob(token: "old", expiresMS: 1_500_000_000)],
                         files: ["/d": blob(token: "fresh", expiresMS: 3_000_000_000)])
        let result = await p.token(forConfigDir: "/d")
        if case .ok(let token) = result { XCTAssertEqual(token.accessToken, "fresh") } else { XCTFail("\(result)") }
    }

    func testExpired() async {
        let svc = Credentials.serviceName(forConfigDir: "/d")
        let p = provider(secrets: [svc: blob(token: "tok", expiresMS: 999_999_000)])  // before now
        let result = await p.token(forConfigDir: "/d")
        XCTAssertEqual(result, .expired)
    }

    func testMissing() async {
        let result = await provider(secrets: [:]).token(forConfigDir: "/d")
        XCTAssertEqual(result, .missing)
    }
}
