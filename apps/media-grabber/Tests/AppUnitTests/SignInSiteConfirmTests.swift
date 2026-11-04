@testable import GrabberKit
@testable import MediaGrabber
import XCTest

@MainActor
final class SignInSiteConfirmTests: XCTestCase {
    private var defaults = UserDefaults.standard
    private var suiteName = ""
    private var logDirectory: URL!

    override func setUp() async throws {
        suiteName = "mg.sitesignin.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        logDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-sitesignin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: logDirectory)
    }

    func testConfirmationCopyNamesTheSite() {
        let request = AppModelDialogs.signInSiteConfirmation(siteName: "YouTube")
        XCTAssertEqual(request.title, "Use sign-in for this site?")
        XCTAssertEqual(request.message, "Use your signed-in browser for YouTube?")
        XCTAssertEqual(request.confirmTitle, "Use sign-in")
        XCTAssertEqual(request.cancelTitle, "Not now")
    }

    func testConfirmAddsTheSiteAndRestarts() async throws {
        let engine = FakeEngine()
        let model = AppModelTestHelpers.makeModel(defaults: defaults, logDirectory: logDirectory, engine: engine)
        model.prefs.cookiesFromBrowser = .safari
        model.prefs.signInScope = .listedSites
        let id = UUID()
        let job = AppModelTestHelpers.jobSnapshot(id: id, url: "https://vimeo.com/1", state: .failed(.ageRestricted))
        model.startConsumerForTesting()
        engine.emit(.snapshot(QueueSnapshot(
            jobs: [job], revision: 1, queueHalt: nil, generatedAt: .now,
            hostRateSummary: [:], isOnline: true
        )))
        try await pollUntil { model.rowStore.rows.contains { $0.id == id } }

        let action = Task { await model.handleRowAction(id, action: .retryWithCookies) }
        try await pollUntil { model.pendingConfirmation != nil }
        model.resolveConfirmation(true, suppressFutures: false)
        await action.value
        try await pollUntil { model.prefs.signInSites == ["vimeo.com"] }

        XCTAssertEqual(model.prefs.signInSites, ["vimeo.com"])
        XCTAssertEqual(engine.retriedWithCookiesIDs, [id])
    }

    func testCancelLeavesTheListAndDoesNotRestart() async throws {
        let engine = FakeEngine()
        let model = AppModelTestHelpers.makeModel(defaults: defaults, logDirectory: logDirectory, engine: engine)
        model.prefs.cookiesFromBrowser = .safari
        model.prefs.signInScope = .listedSites
        let id = UUID()
        let job = AppModelTestHelpers.jobSnapshot(id: id, url: "https://vimeo.com/1", state: .failed(.ageRestricted))
        model.startConsumerForTesting()
        engine.emit(.snapshot(QueueSnapshot(
            jobs: [job], revision: 1, queueHalt: nil, generatedAt: .now,
            hostRateSummary: [:], isOnline: true
        )))
        try await pollUntil { model.rowStore.rows.contains { $0.id == id } }

        let action = Task { await model.handleRowAction(id, action: .retryWithCookies) }
        try await pollUntil { model.pendingConfirmation != nil }
        model.resolveConfirmation(false, suppressFutures: false)
        await action.value

        XCTAssertEqual(model.prefs.signInSites, [])
        XCTAssertEqual(engine.retriedWithCookiesIDs, [])
    }

    func testAllSitesDoesNotAskToAddASite() async {
        let engine = FakeEngine()
        let model = AppModelTestHelpers.makeModel(defaults: defaults, logDirectory: logDirectory, engine: engine)
        model.prefs.cookiesFromBrowser = .safari
        model.prefs.signInScope = .allSites
        let id = UUID()
        await model.handleRowAction(id, action: .retryWithCookies)
        XCTAssertNil(model.pendingConfirmation)
        XCTAssertEqual(model.prefs.signInSites, [])
    }

    func testNoBrowserStillOpensPreferences() async {
        let engine = FakeEngine()
        let model = AppModelTestHelpers.makeModel(defaults: defaults, logDirectory: logDirectory, engine: engine)
        model.prefs.signInScope = .listedSites
        let id = UUID()
        await model.handleRowAction(id, action: .retryWithCookies)
        XCTAssertEqual(model.page, .preferences(.cookies))
        XCTAssertEqual(model.prefs.signInSites, [])
        XCTAssertEqual(engine.retriedWithCookiesIDs, [])
    }

    func testChoosingABrowserAsksBeforeRestartingAnUnlistedSite() async throws {
        let engine = FakeEngine()
        let model = AppModelTestHelpers.makeModel(defaults: defaults, logDirectory: logDirectory, engine: engine)
        model.prefs.signInScope = .listedSites
        let id = UUID()
        let job = AppModelTestHelpers.jobSnapshot(id: id, url: "https://vimeo.com/1", state: .failed(.ageRestricted))
        model.startConsumerForTesting()
        engine.emit(.snapshot(QueueSnapshot(
            jobs: [job], revision: 1, queueHalt: nil, generatedAt: .now,
            hostRateSummary: [:], isOnline: true
        )))
        try await pollUntil { model.rowStore.rows.contains { $0.id == id } }

        await model.handleRowAction(id, action: .retryWithCookies)
        XCTAssertEqual(model.page, .preferences(.cookies))
        model.prefs.cookiesFromBrowser = .safari
        let retry = Task { await model.resolveCookieRetry() }
        try await pollUntil { model.pendingConfirmation != nil }
        model.resolveConfirmation(true, suppressFutures: false)
        await retry.value

        XCTAssertEqual(model.prefs.signInSites, ["vimeo.com"])
        XCTAssertEqual(engine.retriedWithCookiesIDs, [id])
    }

    func testPasteOnAnUnlistedSiteAsksThenProbesAgain() async throws {
        let engine = FakeEngine()
        engine.stubPreview(.failure(.ageRestricted))
        let model = AppModelTestHelpers.makeModel(defaults: defaults, logDirectory: logDirectory, engine: engine)
        model.prefs.cookiesFromBrowser = .safari
        model.prefs.signInScope = .listedSites

        let action = Task { await model.resolvePasted("https://vimeo.com/1") }
        try await pollUntil { model.pendingConfirmation != nil }
        XCTAssertEqual(
            model.probeError,
            "This video is age-restricted. Signing in with your browser may let you download it."
        )
        model.resolveConfirmation(true, suppressFutures: false)
        await action.value

        XCTAssertEqual(model.prefs.signInSites, ["vimeo.com"])
        XCTAssertEqual(engine.previewedURLs.count, 2)
    }

    func testCancelOnAPastedSiteDoesNotAddIt() async throws {
        let engine = FakeEngine()
        engine.stubPreview(.failure(.ageRestricted))
        let model = AppModelTestHelpers.makeModel(defaults: defaults, logDirectory: logDirectory, engine: engine)
        model.prefs.cookiesFromBrowser = .safari
        model.prefs.signInScope = .listedSites

        let action = Task { await model.resolvePasted("https://vimeo.com/1") }
        try await pollUntil { model.pendingConfirmation != nil }
        model.resolveConfirmation(false, suppressFutures: false)
        await action.value

        XCTAssertEqual(model.prefs.signInSites, [])
        XCTAssertEqual(engine.previewedURLs.count, 1)
    }

    private func pollUntil(
        timeout: TimeInterval = 2,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("timed out")
    }
}
