import XCTest
@testable import ClausonaGUI

final class ProfilesDecodingTests: XCTestCase {
    func testFullFile() throws {
        let json = """
        {
          "primarySource": "/Users/test/.claude",
          "activeProfile": "personal",
          "profiles": {
            "personal": { "configDir": "/Users/test/.claude", "email": "a@b.c", "orgName": "Org", "isPrimary": true },
            "work": { "configDir": "/Users/test/.claude-work", "email": "w@b.c", "orgName": "W", "mergeSessions": false, "futureKey": 42 }
          }
        }
        """
        let file = try ProfilesFile.decode(Data(json.utf8))
        XCTAssertEqual(file.activeProfile, "personal")
        XCTAssertEqual(file.profiles.map(\.name), ["personal", "work"])
        XCTAssertEqual(file.profiles[0].configDir, "/Users/test/.claude")
        XCTAssertTrue(file.profiles[0].isPrimary)
        XCTAssertFalse(file.profiles[1].isPrimary)
        XCTAssertEqual(file.profiles[1].email, "w@b.c")
    }

    func testMinimalFile() throws {
        let file = try ProfilesFile.decode(Data("{}".utf8))
        XCTAssertNil(file.activeProfile)
        XCTAssertTrue(file.profiles.isEmpty)
    }

    func testGarbageThrows() {
        XCTAssertThrowsError(try ProfilesFile.decode(Data("not json".utf8)))
    }

    func testProfileWithoutConfigDirSkipped() throws {
        let json = #"{ "profiles": { "broken": { "email": "x@y.z" }, "ok": { "configDir": "/tmp/x" } } }"#
        let file = try ProfilesFile.decode(Data(json.utf8))
        XCTAssertEqual(file.profiles.map(\.name), ["ok"])
    }
}
