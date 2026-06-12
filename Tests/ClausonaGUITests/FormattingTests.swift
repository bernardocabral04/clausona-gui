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

    func testCost() {
        XCTAssertEqual(Formatting.cost(1388.034), "$1,388.03")
        XCTAssertEqual(Formatting.cost(0), "$0.00")
        XCTAssertEqual(Formatting.cost(581.83), "$581.83")
        XCTAssertEqual(Formatting.cost(4500.5), "$4,500.50")
    }

    func testTokens() {
        XCTAssertEqual(Formatting.tokens(2_365_402), "2,365,402")
        XCTAssertEqual(Formatting.tokens(0), "0")
        XCTAssertEqual(Formatting.tokens(694), "694")
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
