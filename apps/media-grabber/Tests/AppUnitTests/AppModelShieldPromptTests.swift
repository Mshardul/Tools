import Foundation
@testable import GrabberKit
@testable import MediaGrabber
import XCTest

@MainActor
final class AppModelShieldPromptTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard
    private var logDirectory: URL!

    override func setUp() async throws {
        suiteName = "mg.shieldprompt.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        logDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-shieldprompt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: logDirectory)
    }

    private func failedProbe(
        url: String,
        shield: ShieldStatus,
        error: MetadataError = .botCheck
    ) async -> AppModel {
        let engine = FakeEngine()
        engine.stubPreview(.failure(error))
        engine.setSnapshot(QueueSnapshot(
            jobs: [], revision: 1, queueHalt: nil, generatedAt: .init(),
            hostRateSummary: [:], isOnline: true, shieldStatus: shield
        ))
        let model = AppModelTestHelpers.makeModel(defaults: defaults, logDirectory: logDirectory, engine: engine)
        await model.resolvePasted(url)
        return model
    }

    private let youtube = "https://www.youtube.com/watch?v=abc"

    func test_youtubeBotCheck_shieldMissing_offersSetUp() async {
        let model = await failedProbe(url: youtube, shield: .missing)
        XCTAssertEqual(model.shieldSetup.probePrompt, .setUp)
        XCTAssertTrue(model.probeError?.contains("isn't set up") ?? false)
    }

    func test_youtubeBotCheck_shieldDown_offersRestart() async {
        let model = await failedProbe(url: youtube, shield: .down)
        XCTAssertEqual(model.shieldSetup.probePrompt, .restart)
    }

    func test_youtubeBotCheck_shieldRunning_offersNoShieldAction() async {
        let model = await failedProbe(url: youtube, shield: .running(port: 1))
        XCTAssertNil(model.shieldSetup.probePrompt)
    }

    func test_otherSiteBotCheck_neverOffersOrMentionsShield() async {
        let model = await failedProbe(url: "https://vimeo.com/123", shield: .missing)
        XCTAssertNil(model.shieldSetup.probePrompt)
        XCTAssertFalse(model.probeError?.contains("shield") ?? true)
    }

    func test_youtubeFailureThatIsNotABotCheck_neverOffersShield() async {
        let model = await failedProbe(url: youtube, shield: .missing, error: .unavailable)
        XCTAssertNil(model.shieldSetup.probePrompt)
        XCTAssertEqual(model.probeError, "This video isn't available.")
    }

    func test_newPasteClearsThePreviousPrompt() async {
        let model = await failedProbe(url: youtube, shield: .missing)
        model.clearResolved()
        XCTAssertNil(model.shieldSetup.probePrompt)
    }
}
