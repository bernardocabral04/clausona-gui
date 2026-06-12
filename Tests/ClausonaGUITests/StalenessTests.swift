import XCTest
@testable import ClausonaGUI

final class StalenessTests: XCTestCase {
    let base = Date(timeIntervalSince1970: 1_000_000)

    func testFreshIsNotStale() {
        XCTAssertFalse(Staleness.isStale(lastSuccess: base, now: base.addingTimeInterval(120), pollInterval: 300))
        XCTAssertFalse(Staleness.isStale(lastSuccess: base, now: base.addingTimeInterval(599), pollInterval: 300))
    }

    func testStaleAfterTwoMissedCycles() {
        XCTAssertTrue(Staleness.isStale(lastSuccess: base, now: base.addingTimeInterval(600), pollInterval: 300))
        XCTAssertTrue(Staleness.isStale(lastSuccess: base, now: base.addingTimeInterval(3600), pollInterval: 300))
    }

    func testNeverUpdatedIsNotStale() {
        XCTAssertFalse(Staleness.isStale(lastSuccess: nil, now: base, pollInterval: 300))
    }
}
