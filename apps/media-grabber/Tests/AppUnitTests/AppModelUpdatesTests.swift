import Foundation
@testable import GrabberKit
@testable import MediaGrabber
import XCTest

@MainActor
final class AppModelUpdatesTests: XCTestCase {
    private struct FakeReleases: GitHubReleaseChecking {
        let tag: String
        func latestRelease(owner _: String, repo _: String) async throws -> GitHubRelease {
            try GitHubRelease(tagName: tag, htmlURL: XCTUnwrap(URL(string: "https://example.com/r/\(tag)")))
        }
    }

    private var suiteName = ""
    private var defaults = UserDefaults.standard
    private var logDirectory: URL!

    override func setUp() async throws {
        suiteName = "mg.updates.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        logDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-updates-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: logDirectory)
    }

    private func makeModel(
        appVersion: String,
        latestTag: String = "media-grabber-v2.0.0",
        opener: FakeOpenURLSink = FakeOpenURLSink()
    ) -> AppModel {
        AppModelTestHelpers.makeModel(
            defaults: defaults,
            logDirectory: logDirectory,
            openURLSink: opener,
            appUpdateChecker: AppUpdateChecker(client: FakeReleases(tag: latestTag)),
            appVersion: appVersion
        )
    }

    private func answerPrompt(_ model: AppModel, _ answer: Bool) async throws {
        for _ in 0 ..< 200 where model.pendingConfirmation == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        model.resolveConfirmation(answer, suppressFutures: false)
    }

    func test_newerRelease_promptsAndOpensReleasePageOnConfirm() async throws {
        let opener = FakeOpenURLSink()
        let model = makeModel(appVersion: "1.0.0", opener: opener)
        async let check: Void = model.checkForAppUpdateOnLaunch()
        try await answerPrompt(model, true)
        await check
        XCTAssertEqual(opener.opened.map(\.absoluteString), ["https://example.com/r/media-grabber-v2.0.0"])
    }

    func test_declined_doesNotOpenAndDoesNotPromptAgainForSameVersion() async throws {
        let opener = FakeOpenURLSink()
        let model = makeModel(appVersion: "1.0.0", opener: opener)
        async let check: Void = model.checkForAppUpdateOnLaunch()
        try await answerPrompt(model, false)
        await check
        XCTAssertTrue(opener.opened.isEmpty)

        await model.checkForAppUpdateOnLaunch()
        XCTAssertNil(model.pendingConfirmation)
    }

    func test_upToDate_noPrompt() async {
        let model = makeModel(appVersion: "2.0.0")
        await model.checkForAppUpdateOnLaunch()
        XCTAssertNil(model.pendingConfirmation)
    }

    func test_devBuild_neverPrompts() async {
        let model = makeModel(appVersion: "0.0.0")
        await model.checkForAppUpdateOnLaunch()
        XCTAssertNil(model.pendingConfirmation)
    }

    func test_autoCheckOff_neverPrompts() async {
        let model = makeModel(appVersion: "1.0.0")
        model.prefs.autoCheckAppUpdates = false
        await model.checkForAppUpdateOnLaunch()
        XCTAssertNil(model.pendingConfirmation)
    }
}
