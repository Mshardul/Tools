@testable import MediaGrabber
import XCTest

final class BannerResolverTests: XCTestCase {
    func testPriorityOrder() {
        XCTAssertEqual(resolveBanner([.depMissing, .networkDown, .circuitOpen]), .depMissing)
        XCTAssertEqual(resolveBanner([.networkDown, .circuitOpen]), .networkDown)
        XCTAssertEqual(resolveBanner([.circuitOpen]), .circuitOpen)
        XCTAssertNil(resolveBanner([]))
    }

    func testDepMissingHasNoBannerCopy() {
        XCTAssertNil(bannerCopy(for: .depMissing, circuitHosts: []) {})
    }

    func testNetworkDownCopyHasNoButton() {
        let content = bannerCopy(for: .networkDown, circuitHosts: []) {}
        XCTAssertNil(content?.buttonTitle)
        XCTAssertNil(content?.action)
        XCTAssertEqual(content?.text.contains("No internet"), true)
    }

    func testCircuitOpenCopyHasRetryButton() {
        let content = bannerCopy(for: .circuitOpen, circuitHosts: ["YouTube"]) {}
        XCTAssertEqual(content?.buttonTitle, "Retry now")
        XCTAssertNotNil(content?.action)
        XCTAssertEqual(content?.text.contains("YouTube"), true)
    }

    func testCircuitOpenMultipleHostsCopy() {
        let content = bannerCopy(for: .circuitOpen, circuitHosts: ["YouTube", "Vimeo"]) {}
        XCTAssertEqual(content?.text.contains("2 sites"), true)
    }
}
