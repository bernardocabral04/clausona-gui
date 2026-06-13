import XCTest
@testable import ClausonaGUI

final class ClausonaFlowTests: XCTestCase {
    func testCommands() {
        let bin = "/Users/u/.local/bin/clausona"
        XCTAssertEqual(ClausonaFlow.add(name: "work").command(binaryPath: bin),
                       "'/Users/u/.local/bin/clausona' add work")
        XCTAssertEqual(ClausonaFlow.login(name: "p2").command(binaryPath: bin),
                       "'/Users/u/.local/bin/clausona' login p2")
        XCTAssertEqual(ClausonaFlow.remove(name: "old").command(binaryPath: bin),
                       "'/Users/u/.local/bin/clausona' remove old")
        XCTAssertEqual(ClausonaFlow.config(name: "work").command(binaryPath: bin),
                       "'/Users/u/.local/bin/clausona' config work")
        XCTAssertEqual(ClausonaFlow.initialSetup.command(binaryPath: bin),
                       "'/Users/u/.local/bin/clausona' init")
    }

    func testBinaryPathWithSpacesIsQuoted() {
        let cmd = ClausonaFlow.initialSetup.command(binaryPath: "/Users/u/my tools/clausona")
        XCTAssertEqual(cmd, "'/Users/u/my tools/clausona' init")
    }
}
