import XCTest
@testable import ClausonaGUI

final class DoctorParserTests: XCTestCase {
    static let realOutput = """
      personal (bernardo.cabral@outlook.com)
        ✔ healthy

      work (bernardo.cabral@scaleits-solutions.com)
        ✘ 4 issues
        ├─ .last-update-result.json replaced an expected shared symlink
        ├─ mcp-needs-auth-cache.json replaced an expected shared symlink
        ├─ stats-cache.json replaced an expected shared symlink
        ╰─ plugins/ marketplaces and known_marketplaces.json are out of sync
           Run clausona repair work to fix

      personal3 (bradasdevelopers@gmail.com)
        ✘ 2 issues
        ├─ .last-update-result.json replaced an expected shared symlink
        ╰─ plugins/ marketplaces and known_marketplaces.json are out of sync
           Run clausona repair personal3 to fix

    """

    func testRealOutput() {
        let result = DoctorParser.parse(Self.realOutput)
        XCTAssertEqual(result["personal"], .healthy)
        guard case .issues(let workIssues)? = result["work"] else { return XCTFail("work not parsed") }
        XCTAssertEqual(workIssues.count, 4)
        XCTAssertEqual(workIssues.first, ".last-update-result.json replaced an expected shared symlink")
        XCTAssertEqual(workIssues.last, "plugins/ marketplaces and known_marketplaces.json are out of sync")
        guard case .issues(let p3)? = result["personal3"] else { return XCTFail("personal3 not parsed") }
        XCTAssertEqual(p3.count, 2)
    }

    func testRepairHintLineIgnored() {
        let result = DoctorParser.parse(Self.realOutput)
        if case .issues(let issues)? = result["work"] {
            XCTAssertFalse(issues.contains { $0.contains("Run clausona repair") })
        }
    }

    func testUnparseableYieldsEmpty() {
        XCTAssertTrue(DoctorParser.parse("random garbage\nnothing here").isEmpty)
    }

    func testSingularIssueForm() {
        let out = """
          alpha (a@b.c)
            ✘ 1 issue
            ╰─ something is wrong
        """
        XCTAssertEqual(DoctorParser.parse(out)["alpha"], .issues(["something is wrong"]))
    }

    func testStripANSI() {
        let colored = "\u{001B}[1mpersonal\u{001B}[0m (\u{001B}[2ma@b.c\u{001B}[0m)\n  \u{001B}[32m✔ healthy\u{001B}[0m"
        let stripped = DoctorParser.stripANSI(colored)
        XCTAssertFalse(stripped.contains("\u{001B}"))
        XCTAssertEqual(DoctorParser.parse(stripped)["personal"], .healthy)
    }
}
