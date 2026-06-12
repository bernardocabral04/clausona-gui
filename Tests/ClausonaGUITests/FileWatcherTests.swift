import XCTest
@testable import ClausonaGUI

@MainActor
final class FileWatcherTests: XCTestCase {
    private func tempFile(_ contents: String) throws -> String {
        let path = NSTemporaryDirectory() + "watch-\(UUID().uuidString).json"
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    func testDetectsInPlaceWrite() async throws {
        let path = try tempFile("one")
        let changed = expectation(description: "change detected")
        changed.assertForOverFulfill = false
        let watcher = FileWatcher(path: path) { changed.fulfill() }
        watcher.start()
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(100))
        let handle = FileHandle(forWritingAtPath: path)!
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("two".utf8))
        try handle.close()

        await fulfillment(of: [changed], timeout: 5)
    }

    func testSurvivesAtomicReplace() async throws {
        let path = try tempFile("one")
        let changes = expectation(description: "two changes detected")
        changes.expectedFulfillmentCount = 2
        changes.assertForOverFulfill = false
        let watcher = FileWatcher(path: path) { changes.fulfill() }
        watcher.start()
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(100))
        try "two".write(toFile: path, atomically: true, encoding: .utf8)   // rename-over
        try await Task.sleep(for: .milliseconds(300))
        try "three".write(toFile: path, atomically: true, encoding: .utf8) // watcher must have re-armed
        await fulfillment(of: [changes], timeout: 5)
    }
}
