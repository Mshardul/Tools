import Foundation
@testable import GrabberKit
@testable import MediaGrabber
import XCTest

@MainActor
final class AppModelOnboardingTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard
    private var logDirectory: URL!

    override func setUp() async throws {
        suiteName = "mg.onboarding.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        logDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-onboarding-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: logDirectory)
    }

    func test_freshInstall_showsOnboarding_evenWhenEverythingIsAlreadyInstalled() async {
        let model = AppModelTestHelpers.makeModel(
            defaults: defaults, logDirectory: logDirectory, envReady: true, onboardingCompleted: false
        )
        await model.refreshOnboardingState()
        XCTAssertTrue(model.needsOnboarding)
    }

    func test_continuing_marksOnboardingDone_andLeavesIt() async {
        let model = AppModelTestHelpers.makeModel(
            defaults: defaults, logDirectory: logDirectory, envReady: true, onboardingCompleted: false
        )
        await model.refreshOnboardingState()
        await model.completeOnboarding()
        XCTAssertTrue(model.hasCompletedOnboarding)
        XCTAssertFalse(model.needsOnboarding)
    }

    func test_afterFirstRun_onboardingOnlyReturnsWhenRequiredToolsDisappear() async {
        let ready = AppModelTestHelpers.makeModel(defaults: defaults, logDirectory: logDirectory, envReady: true)
        await ready.refreshOnboardingState()
        XCTAssertFalse(ready.needsOnboarding)

        let broken = AppModelTestHelpers.makeModel(defaults: defaults, logDirectory: logDirectory, envReady: false)
        await broken.refreshOnboardingState()
        XCTAssertTrue(broken.needsOnboarding)
    }
}
