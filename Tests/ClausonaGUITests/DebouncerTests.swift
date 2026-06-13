import XCTest
@testable import ClausonaGUI

@MainActor
final class DebouncerTests: XCTestCase {
    func testBurstFiresOnce() async throws {
        var fired = 0
        let debouncer = Debouncer(interval: 0.1) { fired += 1 }
        for _ in 0..<5 { debouncer.call() }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(fired, 1)
    }

    func testSeparateBurstsFireSeparately() async throws {
        var fired = 0
        let debouncer = Debouncer(interval: 0.05) { fired += 1 }
        debouncer.call()
        try await Task.sleep(for: .milliseconds(150))
        debouncer.call()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(fired, 2)
    }
}
