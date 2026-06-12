import XCTest
@testable import ClausonaGUI

final class UsageLogTests: XCTestCase {
    static let lisbon: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return cal
    }()

    static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        lisbon.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    func testRealShape() throws {
        let json = """
        {
          "personal": {
            "records": [
              { "ts": "2026-05-12T19:56:52+00:00", "tz": "+00:00", "cost": 0.128298, "inputTokens": 694, "outputTokens": 340 },
              { "ts": "2026-06-11T16:30:49+01:00", "tz": "+01:00", "cost": 144.376668, "inputTokens": 106840, "outputTokens": 485753 }
            ],
            "seenSessions": ["abc"]
          },
          "work": { "records": [], "seenSessions": [] }
        }
        """
        let log = try UsageLog.decode(Data(json.utf8))
        XCTAssertEqual(log.keys.sorted(), ["personal", "work"])
        XCTAssertEqual(log["personal"]?.count, 2)
        // May 12 19:56:52Z == 20:56:52 Lisbon (WEST, +01:00)
        XCTAssertEqual(log["personal"]?[0].ts, Self.date(2026, 5, 12, 20, 56, 52))
        XCTAssertEqual(log["personal"]?[0].cost, 0.128298)
        XCTAssertEqual(log["personal"]?[1].ts, Self.date(2026, 6, 11, 16, 30, 49))
        XCTAssertEqual(log["personal"]?[1].inputTokens, 106840)
        XCTAssertEqual(log["personal"]?[1].outputTokens, 485753)
        XCTAssertEqual(log["work"], [])
    }

    func testMalformedRecordSkippedNotFatal() throws {
        let json = """
        {
          "p": { "records": [
            { "ts": "2026-06-11T10:00:00+01:00", "cost": 1.5, "inputTokens": 1, "outputTokens": 2 },
            { "ts": "not a date", "cost": 9.9, "inputTokens": 1, "outputTokens": 2 },
            { "cost": 9.9 },
            "junk"
          ] }
        }
        """
        let log = try UsageLog.decode(Data(json.utf8))
        XCTAssertEqual(log["p"]?.count, 1)
        XCTAssertEqual(log["p"]?[0].cost, 1.5)
    }

    func testProfileWithoutRecordsTolerated() throws {
        let log = try UsageLog.decode(Data(#"{ "p": { "seenSessions": [] } }"#.utf8))
        XCTAssertEqual(log["p"], [])
    }

    func testGarbageThrows() {
        XCTAssertThrowsError(try UsageLog.decode(Data("nope".utf8)))
    }
}
