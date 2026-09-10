import Foundation
@testable import GrabberKit
@testable import MediaGrabber
import TestSupport
import XCTest

@MainActor
final class AppModelHomeFieldTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard
    private var logDirectory: URL!

    override func setUp() async throws {
        suiteName = "mg.appmodel.home.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        logDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-appmodel-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: logDirectory)
    }

    private func makeModel(engine: FakeEngine = FakeEngine()) -> AppModel {
        AppModelTestHelpers.makeModel(
            defaults: defaults,
            logDirectory: logDirectory,
            engine: engine
        )
    }

    func test_applyIncomingURL_setsHomeFieldTextAndResolves() async throws {
        let engine = FakeEngine()
        engine.stubPreview(.success(AppModelTestHelpers.meta(title: "Incoming Clip")))
        let model = makeModel(engine: engine)
        let url = try XCTUnwrap(URL(string: "https://example.com/watch?v=abc"))
        await model.applyIncomingURL(url)
        XCTAssertEqual(model.homeFieldText, "https://example.com/watch?v=abc")
        XCTAssertEqual(model.resolved?.title, "Incoming Clip")
        XCTAssertEqual(engine.previewedURLs, ["https://example.com/watch?v=abc"])
    }

    func test_isHomeBusy_whenHomeFieldTextNonEmpty() {
        let model = makeModel()
        model.homeFieldText = "https://example.com"
        let busy = model.isHomeBusy
        XCTAssertTrue(busy)
    }

    func test_isHomeBusy_whenProbing() {
        let model = makeModel()
        model.isProbing = true
        let busy = model.isHomeBusy
        XCTAssertTrue(busy)
    }

    func test_isHomeBusy_whenPlaylistPickerPresented() {
        let model = makeModel()
        model.isPlaylistPickerPresented = true
        let busy = model.isHomeBusy
        XCTAssertTrue(busy)
    }

    func test_isHomeBusy_falseWhenIdle() {
        let model = makeModel()
        let busy = model.isHomeBusy
        XCTAssertFalse(busy)
    }
}
