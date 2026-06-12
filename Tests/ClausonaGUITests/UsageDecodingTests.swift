import XCTest
@testable import ClausonaGUI

final class UsageDecodingTests: XCTestCase {
    func testBothWindows() throws {
        let json = """
        {
          "five_hour": { "utilization": 61.4, "resets_at": "2026-06-13T00:29:59.955070+00:00" },
          "seven_day": { "utilization": 52.0, "resets_at": "2026-06-15T12:59:59.955093+00:00" },
          "seven_day_sonnet": { "utilization": 0.0, "resets_at": null },
          "extra_usage": { "is_enabled": false }
        }
        """
        let report = try UsageReport.decode(Data(json.utf8))
        XCTAssertEqual(report.fiveHour?.utilization, 61)
        XCTAssertEqual(report.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_781_310_599))
        XCTAssertEqual(report.sevenDay?.utilization, 52)
        XCTAssertEqual(report.sevenDay?.resetsAt, Date(timeIntervalSince1970: 1_781_528_399))
    }

    func testMissingAndNullWindows() throws {
        let report = try UsageReport.decode(Data(#"{ "five_hour": null }"#.utf8))
        XCTAssertNil(report.fiveHour)
        XCTAssertNil(report.sevenDay)
    }

    func testWindowWithoutReset() throws {
        let report = try UsageReport.decode(Data(#"{ "five_hour": { "utilization": 12.6 } }"#.utf8))
        XCTAssertEqual(report.fiveHour?.utilization, 13)   // rounded
        XCTAssertNil(report.fiveHour?.resetsAt)
    }

    func testMalformedThrows() {
        XCTAssertThrowsError(try UsageReport.decode(Data("oops".utf8)))
    }

    func testAPIDateZuluAndOffset() {
        XCTAssertEqual(APIDate.parse("2026-06-13T00:29:59Z"), Date(timeIntervalSince1970: 1_781_310_599))
        XCTAssertEqual(APIDate.parse("2026-06-13T00:29:59.5+00:00"), Date(timeIntervalSince1970: 1_781_310_599))
        XCTAssertNil(APIDate.parse("yesterday"))
    }
}
