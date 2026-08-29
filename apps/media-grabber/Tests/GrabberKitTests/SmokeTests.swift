@testable import GrabberKit
import XCTest

final class SmokeTests: XCTestCase {
    func test_grabberKitName() {
        XCTAssertEqual(GrabberKit.name, "GrabberKit")
    }
}
