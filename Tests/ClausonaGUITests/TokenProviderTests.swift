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

    // MARK: - Silent refresh

    private func refreshableBlob(token: String, refreshToken: String, expiresMS: Double) -> Data {
        Data(#"{ "claudeAiOauth": { "accessToken": "\#(token)", "refreshToken": "\#(refreshToken)", "expiresAt": \#(expiresMS), "subscriptionType": "max" } }"#.utf8)
    }

    func testExpiredTokenIsSilentlyRefreshedAndPersisted() async {
        let svc = Credentials.serviceName(forConfigDir: "/d")
        nonisolated(unsafe) var written: (service: String, blob: Data)?
        var p = provider(secrets: [svc: refreshableBlob(token: "stale", refreshToken: "rt-1", expiresMS: 999_000_000)])
        p.refresh = { refreshToken in
            XCTAssertEqual(refreshToken, "rt-1")
            return .success(.init(accessToken: "fresh", refreshToken: "rt-2",
                                  expiresAt: Date(timeIntervalSince1970: 2_000_000)))
        }
        p.writeSecret = { service, blob in
            written = (service, blob)
            return true
        }
        let result = await p.token(forConfigDir: "/d")
        guard case .ok(let token) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(token.accessToken, "fresh")
        XCTAssertEqual(written?.service, svc)
        let persisted = Credentials.parse(written?.blob ?? Data())
        XCTAssertEqual(persisted?.accessToken, "fresh")
        XCTAssertEqual(persisted?.refreshToken, "rt-2")
    }

    func testRefreshFailureFallsBackToExpired() async {
        let svc = Credentials.serviceName(forConfigDir: "/d")
        var p = provider(secrets: [svc: refreshableBlob(token: "stale", refreshToken: "rt", expiresMS: 999_000_000)])
        p.refresh = { _ in .failure(.init(message: "HTTP 400")) }
        p.writeSecret = { _, _ in XCTFail("must not write on failed refresh"); return false }
        let result = await p.token(forConfigDir: "/d")
        XCTAssertEqual(result, .expired)
    }

    func testExpiredWithoutRefreshTokenStaysExpired() async {
        let svc = Credentials.serviceName(forConfigDir: "/d")
        var p = provider(secrets: [svc: blob(token: "stale", expiresMS: 999_000_000)])   // no refreshToken
        p.refresh = { _ in XCTFail("must not attempt refresh without a refresh token"); return .failure(.init(message: "x")) }
        let result = await p.token(forConfigDir: "/d")
        XCTAssertEqual(result, .expired)
    }

    func testRefreshSucceedsEvenIfPersistFails() async {
        // The fresh token is still served this cycle; persistence failure only
        // means the next launch re-refreshes.
        let svc = Credentials.serviceName(forConfigDir: "/d")
        var p = provider(secrets: [svc: refreshableBlob(token: "stale", refreshToken: "rt", expiresMS: 999_000_000)])
        p.refresh = { _ in .success(.init(accessToken: "fresh", refreshToken: nil,
                                          expiresAt: Date(timeIntervalSince1970: 2_000_000))) }
        p.writeSecret = { _, _ in false }
        let result = await p.token(forConfigDir: "/d")
        guard case .ok(let token) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(token.accessToken, "fresh")
    }
}
