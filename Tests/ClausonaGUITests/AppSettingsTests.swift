import XCTest
@testable import ClausonaGUI

@MainActor
final class AppSettingsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "clausona-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testDefaults() {
        let settings = AppSettings(defaults: makeDefaults())
        XCTAssertEqual(settings.terminal, .terminal)
        XCTAssertEqual(settings.refreshMinutes, 5)
        XCTAssertNil(settings.otherTerminalPath)
    }

    func testRoundTrip() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.terminal = .warp
        settings.refreshMinutes = 15
        settings.otherTerminalPath = "/Applications/kitty.app"

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.terminal, .warp)
        XCTAssertEqual(reloaded.refreshMinutes, 15)
        XCTAssertEqual(reloaded.otherTerminalPath, "/Applications/kitty.app")
    }

    func testGarbageStoredValueFallsBackToDefault() {
        let defaults = makeDefaults()
        defaults.set("Kitty?", forKey: "terminalChoice")
        defaults.set(99, forKey: "refreshMinutes")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.terminal, .terminal)
        XCTAssertEqual(settings.refreshMinutes, 5)     // not one of 2/5/15
    }
}
