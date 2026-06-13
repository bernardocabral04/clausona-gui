import XCTest
@testable import ClausonaGUI

@MainActor
final class TerminalLauncherTests: XCTestCase {
    func testAppleScriptEscapesQuotesAndBackslashes() {
        let script = TerminalLauncher.appleScript(for: #"'/Users/u/my "tools"/clausona' init"#)
        XCTAssertTrue(script.contains(#"do script "'/Users/u/my \"tools\"/clausona' init""#))
        XCTAssertTrue(script.contains("tell application \"Terminal\""))
        XCTAssertTrue(script.contains("activate"))
    }

    func testWrapperScriptExecsCommandAndSelfDeletes() {
        let body = TerminalLauncher.wrapperScript(for: "'/usr/local/bin/clausona' add work")
        XCTAssertTrue(body.hasPrefix("#!/bin/zsh\n"))
        XCTAssertTrue(body.contains(#"rm -f -- "$0""#))
        XCTAssertTrue(body.contains("exec '/usr/local/bin/clausona' add work"))
        // self-delete must come BEFORE exec (exec never returns)
        let rmIndex = body.range(of: "rm -f")!.lowerBound
        let execIndex = body.range(of: "exec ")!.lowerBound
        XCTAssertLessThan(rmIndex, execIndex)
    }

    func testWriteWrapperCreatesExecutableCommandFile() throws {
        let url = try TerminalLauncher.writeWrapper(for: "echo hello")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.pathExtension, "command")
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.int16Value ?? 0
        XCTAssertEqual(perms & 0o111, 0o111)   // executable
        let body = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(body.contains("echo hello"))
    }
}
