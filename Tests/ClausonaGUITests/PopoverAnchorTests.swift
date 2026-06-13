import XCTest
@testable import ClausonaGUI

final class PopoverAnchorTests: XCTestCase {
    // Bottom-left (AppKit) coordinates throughout. Screen 1512x982.
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    // Button at top of screen: x 819..841.5, y 951.5..980.5 (as measured live).
    let button = CGRect(x: 819, y: 951.5, width: 22.5, height: 29)

    func testCentersUnderButtonAndHangsBelowIt() {
        let misplaced = CGRect(x: 657, y: 982 - 111 - 263, width: 446, height: 263)
        let fixed = PopoverAnchor.correctedFrame(popover: misplaced, buttonScreenRect: button, screen: screen)
        XCTAssertEqual(fixed.midX, button.midX, accuracy: 0.5)
        XCTAssertEqual(fixed.maxY, button.minY, accuracy: 0.5)   // top of popover touches bottom of button
        XCTAssertEqual(fixed.size, misplaced.size)
    }

    func testClampsToRightScreenEdge() {
        let nearEdge = CGRect(x: 1495, y: 951.5, width: 22.5, height: 29)
        let fixed = PopoverAnchor.correctedFrame(popover: CGRect(x: 0, y: 0, width: 446, height: 263),
                                                 buttonScreenRect: nearEdge, screen: screen)
        XCTAssertLessThanOrEqual(fixed.maxX, screen.maxX)
        XCTAssertGreaterThanOrEqual(fixed.minX, screen.minX)
    }

    func testClampsToLeftScreenEdge() {
        let nearEdge = CGRect(x: 4, y: 951.5, width: 22.5, height: 29)
        let fixed = PopoverAnchor.correctedFrame(popover: CGRect(x: 0, y: 0, width: 446, height: 263),
                                                 buttonScreenRect: nearEdge, screen: screen)
        XCTAssertGreaterThanOrEqual(fixed.minX, screen.minX)
    }

    func testNegativeOriginScreen() {
        // External display arranged left of the main one → negative global X.
        let extScreen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let extButton = CGRect(x: -1910, y: 1049, width: 22.5, height: 29)   // near its left edge
        let fixed = PopoverAnchor.correctedFrame(popover: CGRect(x: 0, y: 0, width: 446, height: 263),
                                                 buttonScreenRect: extButton, screen: extScreen)
        XCTAssertGreaterThanOrEqual(fixed.minX, extScreen.minX)
        XCTAssertEqual(fixed.maxY, extButton.minY, accuracy: 0.5)
    }

    func testNeedsCorrectionDetectsDisplacement() {
        let misplaced = CGRect(x: 657, y: 982 - 111 - 263, width: 446, height: 263)
        XCTAssertTrue(PopoverAnchor.needsCorrection(popover: misplaced, buttonScreenRect: button))
        let good = PopoverAnchor.correctedFrame(popover: misplaced, buttonScreenRect: button, screen: screen)
        XCTAssertFalse(PopoverAnchor.needsCorrection(popover: good, buttonScreenRect: button))
    }
}
