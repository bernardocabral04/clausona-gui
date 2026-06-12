import XCTest
@testable import ClausonaGUI

final class UsageRangeTests: XCTestCase {
    static let lisbon: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return cal
    }()

    static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0) -> Date {
        lisbon.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }

    func testThisWeekFromSaturday() {
        let interval = UsageRange.thisWeek.interval(now: Self.date(2026, 6, 13, 12), calendar: Self.lisbon)
        XCTAssertEqual(interval?.start, Self.date(2026, 6, 8))          // Monday 00:00
        XCTAssertEqual(interval?.end, Date.distantFuture)
    }

    func testThisWeekSundayEdge() {
        let interval = UsageRange.thisWeek.interval(now: Self.date(2026, 6, 14, 23), calendar: Self.lisbon)
        XCTAssertEqual(interval?.start, Self.date(2026, 6, 8))          // Sunday still belongs to Mon 6/8 week
    }

    func testThisWeekMondayEdge() {
        let interval = UsageRange.thisWeek.interval(now: Self.date(2026, 6, 8, 0), calendar: Self.lisbon)
        XCTAssertEqual(interval?.start, Self.date(2026, 6, 8))
    }

    func testLastWeekBounded() {
        let interval = UsageRange.lastWeek.interval(now: Self.date(2026, 6, 13, 12), calendar: Self.lisbon)
        XCTAssertEqual(interval?.start, Self.date(2026, 6, 1))
        XCTAssertEqual(interval?.end, Self.date(2026, 6, 8))
    }

    func testThisMonth() {
        let interval = UsageRange.thisMonth.interval(now: Self.date(2026, 6, 13, 12), calendar: Self.lisbon)
        XCTAssertEqual(interval?.start, Self.date(2026, 6, 1))
        XCTAssertEqual(interval?.end, Date.distantFuture)
    }

    func testAllTimeIsNil() {
        XCTAssertNil(UsageRange.allTime.interval(now: Self.date(2026, 6, 13), calendar: Self.lisbon))
    }
}
