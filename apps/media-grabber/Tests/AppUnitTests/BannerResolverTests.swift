@testable import GrabberKit
@testable import MediaGrabber
import XCTest

final class BannerResolverTests: XCTestCase {
    func testPriorityOrder() {
        XCTAssertEqual(resolveBanner([.depMissing, .networkDown, .circuitOpen]), .depMissing)
        XCTAssertEqual(resolveBanner([.networkDown, .circuitOpen]), .networkDown)
        XCTAssertEqual(resolveBanner([.circuitOpen]), .circuitOpen)
        XCTAssertEqual(
            resolveBanner([.circuitOpen, .potProviderDown]),
            .circuitOpen
        )
        XCTAssertEqual(resolveBanner([.potProviderDown]), .potProviderDown)
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

    func testPotProviderDownCopyHasRestartButton() {
        let content = bannerCopy(for: .potProviderDown, circuitHosts: []) {}
        XCTAssertEqual(
            content?.text,
            "The bot-check shield stopped working — some YouTube downloads may fail or be low-res."
        )
        XCTAssertEqual(content?.buttonTitle, "Restart")
        XCTAssertNotNil(content?.action)
    }

    @MainActor
    func testShieldNeverSetUp_showsNoBanner_butStoppedShieldDoes() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let logDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let model = AppModelTestHelpers.makeModel(defaults: defaults, logDirectory: logDir)

        func snapshot(_ shield: ShieldStatus) -> QueueSnapshot {
            QueueSnapshot(
                jobs: [], revision: 1, queueHalt: nil, generatedAt: .init(),
                hostRateSummary: [:], isOnline: true, shieldStatus: shield
            )
        }
        model.recomputeBanner(snapshot(.missing))
        XCTAssertNil(model.bannerContent)
        model.recomputeBanner(snapshot(.down))
        XCTAssertEqual(model.bannerContent?.buttonTitle, "Restart")
        model.recomputeBanner(snapshot(.running(port: 1)))
        XCTAssertNil(model.bannerContent)
    }
}
