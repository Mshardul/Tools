@testable import GrabberKit
import XCTest

final class SmokeTests: XCTestCase {
    func test_engineProtocolIsReachable() {
        let deps = EngineDependencies.live(ytDlpURL: URL(fileURLWithPath: "/bin/echo"))
        XCTAssertEqual(deps.ytDlpURL.lastPathComponent, "echo")
    }
}
