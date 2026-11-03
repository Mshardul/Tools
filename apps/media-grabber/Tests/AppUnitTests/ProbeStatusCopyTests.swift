@testable import MediaGrabber
import XCTest

final class ProbeStatusCopyTests: XCTestCase {
    func test_checkingCopyIsPlainAndNamesTheAction() {
        XCTAssertEqual(ProbeStatusCopy.checking, "Checking link…")
    }
}
