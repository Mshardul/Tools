import Foundation
@testable import GrabberKit
@testable import MediaGrabber
import TestSupport
import XCTest

@MainActor
final class AppModelRowActionTests: XCTestCase {
    private var defaults = UserDefaults.standard
    private var suiteName = ""
    private var logDirectory: URL!

    override func setUp() async throws {
        suiteName = "mg.rowactions.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        logDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-rowactions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: logDirectory)
    }

    private func makeModel(
        engine: FakeEngine = FakeEngine(),
        openURLSink: FakeOpenURLSink = FakeOpenURLSink(),
        engineJobLogDir: URL? = nil
    ) -> AppModel {
        AppModelTestHelpers.makeModel(
            defaults: defaults,
            logDirectory: logDirectory,
            engine: engine,
            openURLSink: openURLSink,
            engineJobLogDir: engineJobLogDir
        )
    }

    func test_consumerTask_appliesEventsToRowStore() async throws {
        let engine = FakeEngine()
        let model = makeModel(engine: engine)
        await model.onAppear()

        let job = AppModelTestHelpers.jobSnapshot()
        engine.emit(.snapshot(QueueSnapshot(
            jobs: [job],
            revision: 1,
            queueHalt: nil,
            generatedAt: .init()
        )))

        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.rowStore.rows.count, 1)
        XCTAssertEqual(model.rowStore.rows.first?.id, job.id)
    }

    func test_handleRowAction_retryCallsEngineRetry() async {
        let engine = FakeEngine()
        let model = makeModel(engine: engine)
        let id = UUID()
        await model.handleRowAction(id, action: .retry)
        XCTAssertEqual(engine.retriedIDs, [id])
    }

    func test_handleRowAction_showLogExistingFileOpensIt() async throws {
        let sink = FakeOpenURLSink()
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-showlog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let id = UUID()
        let file = dir.appendingPathComponent("\(id.uuidString).log")
        FileManager.default.createFile(atPath: file.path, contents: Data("log".utf8))
        let model = makeModel(openURLSink: sink, engineJobLogDir: dir)

        await model.handleRowAction(id, action: .showLog)
        XCTAssertEqual(sink.opened, [file])
        XCTAssertNil(model.pendingConfirmation)
    }

    func test_handleRowAction_showLogMissingFileShowsNoticeAndLogs() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-showlog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = makeModel(engineJobLogDir: dir)
        let id = UUID()

        let action = Task { await model.handleRowAction(id, action: .showLog) }
        try await pollUntil { model.pendingConfirmation != nil }
        XCTAssertNil(model.pendingConfirmation?.cancelTitle)
        model.resolveConfirmation(true, suppressFutures: false)
        await action.value
        XCTAssertTrue(
            try AppModelTestHelpers.logContainsEvent("show_log.target_missing", in: logDirectory)
        )
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
        XCTFail("condition never became true")
    }
}
