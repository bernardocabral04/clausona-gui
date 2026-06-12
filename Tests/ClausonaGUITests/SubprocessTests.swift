import XCTest
@testable import ClausonaGUI

final class SubprocessTests: XCTestCase {
    func testCapturesStdoutAndExitCode() async {
        let result = await Subprocess.run("/bin/echo", ["hello"])
        XCTAssertEqual(result?.exitCode, 0)
        XCTAssertEqual(result?.stdout, "hello\n")
        XCTAssertEqual(result?.stderr, "")
    }

    func testNonZeroExitAndStderr() async {
        let result = await Subprocess.run("/bin/sh", ["-c", "echo bad >&2; exit 3"])
        XCTAssertEqual(result?.exitCode, 3)
        XCTAssertEqual(result?.stderr, "bad\n")
    }

    func testMissingExecutableReturnsNil() async {
        let result = await Subprocess.run("/no/such/binary", [])
        XCTAssertNil(result)
    }
}
