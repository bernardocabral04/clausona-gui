import XCTest
import AppKit
@testable import ClausonaGUI

final class MenuBarIconTests: XCTestCase {
    func testBuildsTemplateImage() {
        let image = MenuBarIcon.image()
        XCTAssertNotNil(image)
        XCTAssertTrue(image?.isTemplate == true)
        // Sized for the menu bar (square, ~18pt).
        XCTAssertEqual(image?.size.width, image?.size.height)
        XCTAssertEqual(image?.size.width ?? 0, 18, accuracy: 0.01)
    }

    func testEmbeddedSVGMatchesAsset() throws {
        // The in-code SVG must stay byte-identical to the design asset so the
        // menu bar icon never drifts from Resources/MenuBarIcon.svg.
        let assetURL = URL(fileURLWithPath: #filePath)        // .../Tests/ClausonaGUITests/MenuBarIconTests.swift
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/MenuBarIcon.svg")
        let onDisk = try String(contentsOf: assetURL, encoding: .utf8)
        XCTAssertEqual(MenuBarIcon.svg, onDisk)
    }
}
