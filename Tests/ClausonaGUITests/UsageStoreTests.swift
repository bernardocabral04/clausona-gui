import XCTest
@testable import ClausonaGUI

@MainActor
final class UsageStoreTests: XCTestCase {
    nonisolated static let lisbon: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return cal
    }()
    nonisolated static let now = lisbon.date(from: DateComponents(year: 2026, month: 6, day: 13, hour: 12))!

    private func makeHome(usageJSON: String?) throws -> String {
        let dir = NSTemporaryDirectory() + "clausona-home-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let usageJSON {
            try usageJSON.write(toFile: dir + "/usage.json", atomically: true, encoding: .utf8)
        }
        return dir
    }

    func testLoadAndAggregate() throws {
        let home = try makeHome(usageJSON: """
        {
          "personal": { "records": [
            { "ts": "2026-06-09T10:00:00+01:00", "tz": "+01:00", "cost": 1.5, "inputTokens": 100, "outputTokens": 200 },
            { "ts": "2026-06-01T10:00:00+01:00", "tz": "+01:00", "cost": 8.0, "inputTokens": 1, "outputTokens": 1 }
          ] },
          "work": { "records": [
            { "ts": "2026-06-12T09:00:00+01:00", "tz": "+01:00", "cost": 2.5, "inputTokens": 10, "outputTokens": 20 }
          ] }
        }
        """)
        let store = UsageStore(environment: ["CLAUSONA_HOME": home],
                               calendar: Self.lisbon, now: { Self.now })
        store.reload()
        XCTAssertFalse(store.loadFailed)
        XCTAssertEqual(store.range, .thisWeek)
        // This week = Mon 6/8 onward: 1.5 + 2.5
        XCTAssertEqual(store.grandTotalCost(), 4.0, accuracy: 0.0001)
        XCTAssertEqual(store.totalsByProfile()["personal"]?.cost ?? 0, 1.5, accuracy: 0.0001)
        XCTAssertEqual(store.dailyCosts().count, 2)

        store.range = .allTime
        XCTAssertEqual(store.grandTotalCost(), 12.0, accuracy: 0.0001)
    }

    func testMissingFileIsLoadFailed() throws {
        let home = try makeHome(usageJSON: nil)
        let store = UsageStore(environment: ["CLAUSONA_HOME": home],
                               calendar: Self.lisbon, now: { Self.now })
        store.reload()
        XCTAssertTrue(store.loadFailed)
        XCTAssertEqual(store.grandTotalCost(), 0)
        XCTAssertTrue(store.dailyCosts().isEmpty)
    }
}
