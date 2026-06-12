import XCTest
@testable import ClausonaGUI

final class ClausonaCLITests: XCTestCase {
    func testLocatePrefersLocalBinThenPATH() {
        let found = ClausonaCLI.locate(environment: ["PATH": "/a:/b"], home: "/home/u",
                                       fileExists: { $0 == "/home/u/.local/bin/clausona" })
        XCTAssertEqual(found, "/home/u/.local/bin/clausona")

        let viaPath = ClausonaCLI.locate(environment: ["PATH": "/a:/b"], home: "/home/u",
                                         fileExists: { $0 == "/b/clausona" })
        XCTAssertEqual(viaPath, "/b/clausona")

        XCTAssertNil(ClausonaCLI.locate(environment: ["PATH": "/a"], home: "/home/u", fileExists: { _ in false }))
    }

    private func makeStub(_ body: String) throws -> String {
        let dir = NSTemporaryDirectory() + "clausona-cli-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/clausona"
        try ("#!/bin/sh\n" + body).write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    func testUseSuccess() async throws {
        let stub = try makeStub("[ \"$1\" = use ] && [ \"$2\" = work ] && exit 0; exit 1")
        let result = await ClausonaCLI(binaryPath: stub).use(profile: "work")
        guard case .success = result else { return XCTFail("\(result)") }
    }

    func testRepairFailureSurfacesFirstStderrLine() async throws {
        let stub = try makeStub("echo 'repair failed: profile is locked' >&2; echo second >&2; exit 2")
        let result = await ClausonaCLI(binaryPath: stub).repair(profile: "work")
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error.message, "repair failed: profile is locked")
    }

    func testFailureWithoutOutputFallsBackToStatus() async throws {
        let stub = try makeStub("exit 7")
        let result = await ClausonaCLI(binaryPath: stub).use(profile: "x")
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error.message, "clausona exited with status 7")
    }

    func testDoctorReturnsStdout() async throws {
        let stub = try makeStub("echo '  personal (a@b.c)'; echo '    ✔ healthy'")
        let output = await ClausonaCLI(binaryPath: stub).doctor()
        XCTAssertEqual(output?.contains("✔ healthy"), true)
    }
}
