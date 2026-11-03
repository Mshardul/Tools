@testable import GrabberKit
@testable import MediaGrabber
import TestSupport
import XCTest

@MainActor
final class PasscodePromptTests: XCTestCase {
    private var logDir: URL!
    private let url = "https://example.zoom.us/rec/share/abc"

    override func setUp() {
        super.setUp()
        logDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-passcode-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: logDir)
        super.tearDown()
    }

    private func makeModel(preview: Result<MediaMetadata, MetadataError>) -> (AppModel, FakeEngine) {
        let engine = FakeEngine()
        engine.stubPreview(preview)
        let model = AppModelTestHelpers.makeModel(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            logDirectory: logDir,
            engine: engine
        )
        return (model, engine)
    }

    private var clip: MediaMetadata {
        MediaMetadata(title: "Clip", durationSeconds: 10, isPlaylist: false, sourceURL: url, extractor: "zoom")
    }

    private func addFailedRow(_ model: AppModel, id: UUID, errorClass: ErrorClass) {
        let snapshot = QueueSnapshot(
            jobs: [AppModelTestHelpers.jobSnapshot(id: id, state: .failed(errorClass))],
            revision: 1, queueHalt: nil, generatedAt: .init(), hostRateSummary: [:], isOnline: true
        )
        model.rowStore.apply(.snapshot(snapshot))
    }

    func test_probePasscodeRequired_opensSheetAndSetsMessage() async {
        let (model, _) = makeModel(preview: .failure(.passcodeRequired))
        await model.resolvePasted(url)
        XCTAssertTrue(model.isPasscodeSheetShown)
        XCTAssertEqual(model.passcodeNeeded, PasscodePrompt(target: .link(url), url: url, wasRejected: false))
        XCTAssertEqual(model.probeError, "This recording needs a passcode.")
    }

    func test_probePasscodeRejected_setsWasRejected() async {
        let (model, _) = makeModel(preview: .failure(.passcodeRejected))
        await model.resolvePasted(url)
        XCTAssertEqual(model.passcodeNeeded, PasscodePrompt(target: .link(url), url: url, wasRejected: true))
        XCTAssertEqual(model.probeError, "That passcode didn't work.")
    }

    func test_submitPasscode_link_savesThenReprobes() async {
        let (model, engine) = makeModel(preview: .failure(.passcodeRequired))
        await model.resolvePasted(url)
        engine.stubPreview(.success(clip))
        await model.submitPasscode("secret")
        XCTAssertEqual(engine.passcodeCalls.setCalls.map(\.passcode), ["secret"])
        XCTAssertEqual(engine.passcodeCalls.setCalls.map(\.url), [url])
        XCTAssertEqual(engine.previewedURLs, [url, url])
        XCTAssertFalse(model.isPasscodeSheetShown)
        XCTAssertNil(model.passcodeNeeded)
        XCTAssertNil(model.probeError)
    }

    func test_submitPasscode_wrongAgain_reopensSheetRejected() async {
        let (model, engine) = makeModel(preview: .failure(.passcodeRequired))
        await model.resolvePasted(url)
        engine.stubPreview(.failure(.passcodeRejected))
        await model.submitPasscode("nope")
        XCTAssertTrue(model.isPasscodeSheetShown)
        XCTAssertEqual(model.passcodeNeeded?.wasRejected, true)
        XCTAssertFalse(model.isProbing)
        engine.stubPreview(.failure(.passcodeRejected))
        await model.submitPasscode("nope again")
        XCTAssertTrue(model.isPasscodeSheetShown)
        XCTAssertEqual(model.passcodeNeeded?.wasRejected, true)
        XCTAssertFalse(model.isProbing)
    }

    func test_submitPasscode_trimsAndIgnoresEmpty() async {
        let (model, engine) = makeModel(preview: .failure(.passcodeRequired))
        await model.resolvePasted(url)
        engine.stubPreview(.success(clip))
        await model.submitPasscode("   ")
        XCTAssertTrue(engine.passcodeCalls.setCalls.isEmpty)
        XCTAssertTrue(model.isPasscodeSheetShown)
        await model.submitPasscode("  p\n")
        XCTAssertEqual(engine.passcodeCalls.setCalls.map(\.passcode), ["p"])
    }

    func test_enterPasscodeRowAction_opensSheetForJob() async {
        let (model, _) = makeModel(preview: .failure(.malformedOutput))
        let id = UUID()
        addFailedRow(model, id: id, errorClass: .passcodeRejected)
        await model.handleRowAction(id, action: .enterPasscode)
        XCTAssertTrue(model.isPasscodeSheetShown)
        XCTAssertEqual(
            model.passcodeNeeded,
            PasscodePrompt(target: .job(id), url: "https://example.com/v", wasRejected: true)
        )
    }

    func test_enterPasscodeRowAction_required_isNotMarkedRejected() async {
        let (model, _) = makeModel(preview: .failure(.malformedOutput))
        let id = UUID()
        addFailedRow(model, id: id, errorClass: .passcodeRequired)
        await model.handleRowAction(id, action: .enterPasscode)
        XCTAssertEqual(model.passcodeNeeded?.wasRejected, false)
    }

    func test_submitPasscode_job_callsRetryWithPasscode() async {
        let (model, engine) = makeModel(preview: .failure(.malformedOutput))
        let id = UUID()
        addFailedRow(model, id: id, errorClass: .passcodeRequired)
        await model.handleRowAction(id, action: .enterPasscode)
        await model.submitPasscode(" p ")
        XCTAssertEqual(engine.passcodeCalls.retryCalls.map(\.id), [id])
        XCTAssertEqual(engine.passcodeCalls.retryCalls.map(\.passcode), ["p"])
        XCTAssertFalse(model.isPasscodeSheetShown)
        XCTAssertNil(model.passcodeNeeded)
    }

    func test_cancel_keepsNeededForLink() async {
        let (model, _) = makeModel(preview: .failure(.passcodeRequired))
        await model.resolvePasted(url)
        model.cancelPasscodePrompt()
        XCTAssertFalse(model.isPasscodeSheetShown)
        XCTAssertEqual(model.passcodeNeeded?.target, .link(url))
    }

    func test_newPasteClearsThePrompt() async {
        let (model, engine) = makeModel(preview: .failure(.passcodeRequired))
        await model.resolvePasted(url)
        engine.stubPreview(.success(clip))
        await model.resolvePasted("https://example.com/other")
        XCTAssertNil(model.passcodeNeeded)
        XCTAssertFalse(model.isPasscodeSheetShown)
    }
}
