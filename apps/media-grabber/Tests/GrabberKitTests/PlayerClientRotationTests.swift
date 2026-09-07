@testable import GrabberKit
import XCTest

final class PlayerClientRotationTests: XCTestCase {
    func testAttemptZeroIsTv() {
        XCTAssertEqual(PlayerClientRotation.client(forAttempt: 0), "tv")
    }

    func testAttemptFourIsWebSafari() {
        XCTAssertEqual(PlayerClientRotation.client(forAttempt: 4), "web_safari")
    }

    func testAttemptPastEndSticks() {
        XCTAssertEqual(PlayerClientRotation.client(forAttempt: 99), "web_safari")
    }

    func testSkipsWebAndAndroid() {
        XCTAssertFalse(PlayerClientRotation.default.contains("web"))
        XCTAssertFalse(PlayerClientRotation.default.contains("android"))
    }
}
