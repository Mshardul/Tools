import Foundation
@testable import GrabberKit
@testable import MediaGrabber
import TestSupport
import XCTest

@MainActor
final class AppModelJobTransitionsTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard
    private var logDirectory: URL!

    override func setUp() async throws {
        suiteName = "mg.appmodel.transitions.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        logDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-appmodel-transitions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: logDirectory)
    }

    private func makeModel(
        engine: FakeEngine = FakeEngine(),
        notificationRouter: (any NotificationRouting)? = nil
    ) -> AppModel {
        AppModelTestHelpers.makeModel(
            defaults: defaults,
            logDirectory: logDirectory,
            engine: engine,
            notificationRouter: notificationRouter
        )
    }

    func test_jobTransitionToCompleted_whileActive_enqueuesSuccessToast() async throws {
        let engine = FakeEngine()
        let model = makeModel(engine: engine)
        model.isAppActive = { true }

        let jobID = UUID()
        let running = AppModelTestHelpers.jobSnapshot(id: jobID, state: .running)
        engine.emit(.snapshot(QueueSnapshot(
            jobs: [running], revision: 1, queueHalt: nil, generatedAt: .now,
            hostRateSummary: [:], isOnline: true
        )))
        model.startConsumerForTesting()
        try await Task.sleep(for: .milliseconds(50))

        let completed = AppModelTestHelpers.jobSnapshot(id: jobID, state: .completed)
        engine.emit(.snapshot(QueueSnapshot(
            jobs: [completed], revision: 2, queueHalt: nil, generatedAt: .now,
            hostRateSummary: [:], isOnline: true
        )))
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(model.toastCenter.items.count, 1)
        XCTAssertTrue(model.toastCenter.items.first?.text.contains("saved") ?? false)
    }

    func test_jobTransitionToFailed_whileBackgrounded_firesNotificationNotToast() async throws {
        let engine = FakeEngine()
        let router = FakeNotificationRouter()
        let model = makeModel(engine: engine, notificationRouter: router)
        model.isAppActive = { false }

        let jobID = UUID()
        let running = AppModelTestHelpers.jobSnapshot(id: jobID, state: .running)
        engine.emit(.snapshot(QueueSnapshot(
            jobs: [running], revision: 1, queueHalt: nil, generatedAt: .now,
            hostRateSummary: [:], isOnline: true
        )))
        model.startConsumerForTesting()
        try await Task.sleep(for: .milliseconds(50))

        let failed = AppModelTestHelpers.jobSnapshot(id: jobID, state: .failed(.networkDown))
        engine.emit(.snapshot(QueueSnapshot(
            jobs: [failed], revision: 2, queueHalt: nil, generatedAt: .now,
            hostRateSummary: [:], isOnline: true
        )))
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(model.toastCenter.items.count, 0)
        XCTAssertEqual(router.notifiedFailures.count, 1)
    }

    func test_jobTransitionToFailed_whileActive_doesNotToastOrNotify() async throws {
        let engine = FakeEngine()
        let router = FakeNotificationRouter()
        let model = makeModel(engine: engine, notificationRouter: router)
        model.isAppActive = { true }

        let jobID = UUID()
        let running = AppModelTestHelpers.jobSnapshot(id: jobID, state: .running)
        engine.emit(.snapshot(QueueSnapshot(
            jobs: [running], revision: 1, queueHalt: nil, generatedAt: .now,
            hostRateSummary: [:], isOnline: true
        )))
        model.startConsumerForTesting()
        try await Task.sleep(for: .milliseconds(50))

        let failed = AppModelTestHelpers.jobSnapshot(id: jobID, state: .failed(.networkDown))
        engine.emit(.snapshot(QueueSnapshot(
            jobs: [failed], revision: 2, queueHalt: nil, generatedAt: .now,
            hostRateSummary: [:], isOnline: true
        )))
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(model.toastCenter.items.count, 0)
        XCTAssertEqual(router.notifiedFailures.count, 0)
    }
}
