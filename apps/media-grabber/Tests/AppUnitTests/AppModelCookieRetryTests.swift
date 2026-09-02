@testable import GrabberKit
@testable import MediaGrabber
import TestSupport
import XCTest

@MainActor
final class AppModelCookieRetryTests: XCTestCase {
    private var logDir: URL!

    override func setUp() {
        super.setUp()
        logDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-cookieretry-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: logDir)
        super.tearDown()
    }

    private func makeModel(_ source: CookieSource) -> (AppModel, FakeEngine) {
        let engine = FakeEngine()
        let model = AppModelTestHelpers.makeModel(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            logDirectory: logDir,
            engine: engine
        )
        model.prefs.cookiesFromBrowser = source
        return (model, engine)
    }

    func test_noBrowser_setsPendingAndOpensPane() async {
        let (model, engine) = makeModel(.none)
        let id = UUID()
        await model.handleRowAction(id, action: .retryWithCookies)
        XCTAssertEqual(model.pendingCookieRetryJobID, id)
        XCTAssertEqual(model.page, .preferences(.cookies))
        XCTAssertTrue(engine.retriedWithCookiesIDs.isEmpty)
    }

    func test_browserSet_callsEngineNoPageChange() async {
        let (model, engine) = makeModel(.safari)
        let id = UUID()
        await model.handleRowAction(id, action: .retryWithCookies)
        XCTAssertEqual(engine.retriedWithCookiesIDs, [id])
        XCTAssertEqual(model.page, .home)
    }

    func test_resolveCookieRetry_firesAndClears() async {
        let (model, engine) = makeModel(.none)
        let id = UUID()
        await model.handleRowAction(id, action: .retryWithCookies)
        await model.resolveCookieRetry()
        XCTAssertEqual(engine.retriedWithCookiesIDs, [id])
        XCTAssertNil(model.pendingCookieRetryJobID)
    }

    func test_resolveCookieRetry_noPending_isNoOp() async {
        let (model, engine) = makeModel(.none)
        await model.resolveCookieRetry()
        XCTAssertTrue(engine.retriedWithCookiesIDs.isEmpty)
    }

    func test_pageChangeAwayFromCookies_clearsPending() async {
        let (model, engine) = makeModel(.none)
        let id = UUID()
        await model.handleRowAction(id, action: .retryWithCookies)
        model.page = .home
        XCTAssertNil(model.pendingCookieRetryJobID)
        XCTAssertTrue(engine.retriedWithCookiesIDs.isEmpty)
    }
}
