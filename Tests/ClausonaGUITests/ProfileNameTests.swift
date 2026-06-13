import XCTest
@testable import ClausonaGUI

final class ProfileNameTests: XCTestCase {
    func testValidNames() {
        XCTAssertTrue(ProfileName.isValid("personal"))
        XCTAssertTrue(ProfileName.isValid("work-belen"))
        XCTAssertTrue(ProfileName.isValid("p2"))
        XCTAssertTrue(ProfileName.isValid("123"))
    }

    func testInvalidNames() {
        XCTAssertFalse(ProfileName.isValid(""))
        XCTAssertFalse(ProfileName.isValid("Work"))          // uppercase
        XCTAssertFalse(ProfileName.isValid("my profile"))    // space
        XCTAssertFalse(ProfileName.isValid("nome_novo"))     // underscore
        XCTAssertFalse(ProfileName.isValid("a;rm -rf ~"))    // shell metacharacters
        XCTAssertFalse(ProfileName.isValid("café"))          // non-ascii
    }
}
