import XCTest
@testable import ClausonaGUI

final class UsageMathTests: XCTestCase {
    static let lisbon: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return cal
    }()

    static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0) -> Date {
        lisbon.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }

    static func rec(_ d: Date, cost: Double, input: Int = 10, output: Int = 20) -> UsageRecord {
        UsageRecord(ts: d, cost: cost, inputTokens: input, outputTokens: output)
    }

    func testTotalsFiltersByIntervalEndExclusive() {
        let interval = DateInterval(start: Self.date(2026, 6, 8), end: Self.date(2026, 6, 15))
        let records = [
            Self.rec(Self.date(2026, 6, 7, 23), cost: 100),          // before start: excluded
            Self.rec(Self.date(2026, 6, 8, 0), cost: 1.5, input: 1, output: 2),   // at start: included
            Self.rec(Self.date(2026, 6, 12), cost: 2.25, input: 3, output: 4),
            Self.rec(Self.date(2026, 6, 15, 0), cost: 50),           // at end: excluded
        ]
        let totals = UsageMath.totals(records, in: interval)
        XCTAssertEqual(totals.cost, 3.75, accuracy: 0.0001)
        XCTAssertEqual(totals.inputTokens, 4)
        XCTAssertEqual(totals.outputTokens, 6)
    }

    func testTotalsNilIntervalSumsEverything() {
        let records = [Self.rec(Self.date(2020, 1, 1), cost: 1), Self.rec(Self.date(2026, 6, 1), cost: 2)]
        XCTAssertEqual(UsageMath.totals(records, in: nil).cost, 3, accuracy: 0.0001)
    }

    func testTotalsByProfile() {
        let byProfile = [
            "a": [Self.rec(Self.date(2026, 6, 9), cost: 1)],
            "b": [Self.rec(Self.date(2026, 6, 9), cost: 2), Self.rec(Self.date(2026, 6, 10), cost: 3)],
        ]
        let totals = UsageMath.totalsByProfile(byProfile, in: nil)
        XCTAssertEqual(totals["a"]?.cost, 1)
        XCTAssertEqual(totals["b"]?.cost ?? 0, 5, accuracy: 0.0001)
    }

    func testDailyCostsStacksByDayThenProfile() {
        let byProfile = [
            "b": [Self.rec(Self.date(2026, 6, 9, 8), cost: 1), Self.rec(Self.date(2026, 6, 9, 22), cost: 2)],
            "a": [Self.rec(Self.date(2026, 6, 9, 12), cost: 4), Self.rec(Self.date(2026, 6, 10, 1), cost: 8)],
        ]
        let daily = UsageMath.dailyCosts(byProfile, in: nil, calendar: Self.lisbon)
        XCTAssertEqual(daily, [
            DailyProfileCost(day: Self.date(2026, 6, 9), profile: "a", cost: 4),
            DailyProfileCost(day: Self.date(2026, 6, 9), profile: "b", cost: 3),
            DailyProfileCost(day: Self.date(2026, 6, 10), profile: "a", cost: 8),
        ])
    }

    func testDailyCostsRespectsInterval() {
        let byProfile = ["a": [Self.rec(Self.date(2026, 6, 1), cost: 1), Self.rec(Self.date(2026, 6, 9), cost: 2)]]
        let interval = DateInterval(start: Self.date(2026, 6, 8), end: .distantFuture)
        let daily = UsageMath.dailyCosts(byProfile, in: interval, calendar: Self.lisbon)
        XCTAssertEqual(daily, [DailyProfileCost(day: Self.date(2026, 6, 9), profile: "a", cost: 2)])
    }
}
