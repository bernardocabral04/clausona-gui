import XCTest
@testable import ClausonaGUI

final class SmokeTests: XCTestCase {
    func testProfileRoundTrip() {
        let p = Profile(name: "personal", configDir: "/Users/test/.claude", email: nil, orgName: nil, isPrimary: true)
        XCTAssertEqual(p.name, "personal")
    }
}
