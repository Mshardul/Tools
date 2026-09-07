@testable import GrabberKit
import TestSupport
import XCTest

final class VPNDetectingTests: XCTestCase {
    func testFakeDefaultsInactive() {
        XCTAssertFalse(FakeVPNDetector().isVPNActive)
    }

    func testFakeCanBeActive() {
        XCTAssertTrue(FakeVPNDetector(isVPNActive: true).isVPNActive)
    }
}
