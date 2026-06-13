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
        XCTAssertNil(settings.otherTerminalPath)
    }

    func testRoundTrip() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.terminal = .warp
        settings.otherTerminalPath = "/Applications/kitty.app"

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.terminal, .warp)
        XCTAssertEqual(reloaded.otherTerminalPath, "/Applications/kitty.app")
    }

    func testGarbageStoredValueFallsBackToDefault() {
        let defaults = makeDefaults()
        defaults.set("Kitty?", forKey: "terminalChoice")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.terminal, .terminal)
    }
}
