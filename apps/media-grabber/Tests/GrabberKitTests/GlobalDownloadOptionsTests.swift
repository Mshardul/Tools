@testable import GrabberKit
import XCTest

final class GlobalDownloadOptionsTests: XCTestCase {
    func test_none() {
        let none = GlobalDownloadOptions.none
        XCTAssertNil(none.proxyURL)
        XCTAssertFalse(none.forceIPv4)
        XCTAssertEqual(none.speedLimitKBps, 0)
    }

    func test_equatable() {
        XCTAssertEqual(
            GlobalDownloadOptions.none,
            GlobalDownloadOptions(proxyURL: nil, forceIPv4: false, speedLimitKBps: 0)
        )
    }
}
