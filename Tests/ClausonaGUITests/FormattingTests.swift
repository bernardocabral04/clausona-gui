import XCTest
@testable import ClausonaGUI

final class FormattingTests: XCTestCase {
    func testDuration() {
        XCTAssertEqual(Formatting.duration(seconds: 3 * 3600 + 42 * 60), "3h42m")
        XCTAssertEqual(Formatting.duration(seconds: 2 * 86400 + 4 * 3600), "2d4h")
        XCTAssertEqual(Formatting.duration(seconds: 5 * 60), "5m")
        XCTAssertEqual(Formatting.duration(seconds: 3601), "1h00m")
        XCTAssertEqual(Formatting.duration(seconds: 0), "0m")
        XCTAssertEqual(Formatting.duration(seconds: -5), "?")
    }

    func testUpdatedAgo() {
        XCTAssertEqual(Formatting.updatedAgo(seconds: 12), "just now")
        XCTAssertEqual(Formatting.updatedAgo(seconds: 140), "2m ago")
        XCTAssertEqual(Formatting.updatedAgo(seconds: 2 * 3600 + 60), "2h ago")
        XCTAssertEqual(Formatting.updatedAgo(seconds: 3 * 86400), "3d ago")
    }

    func testSeverity() {
        XCTAssertEqual(UsageSeverity(percent: 0), .normal)
        XCTAssertEqual(UsageSeverity(percent: 69), .normal)
        XCTAssertEqual(UsageSeverity(percent: 70), .elevated)
        XCTAssertEqual(UsageSeverity(percent: 89), .elevated)
        XCTAssertEqual(UsageSeverity(percent: 90), .critical)
        XCTAssertEqual(UsageSeverity(percent: 100), .critical)
    }
}
