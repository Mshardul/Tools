import Foundation
@testable import GrabberKit
@testable import MediaGrabber
import TestSupport
import XCTest

@MainActor
final class AppModelBatchActionTests: XCTestCase {
    private var defaults = UserDefaults.standard
    private var suiteName = ""
    private var logDirectory: URL!

    override func setUp() async throws {
        suiteName = "mg.batch.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        logDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-batch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: logDirectory)
    }

    func test_clearTableSelectionClearsRowStoreSelection() {
        let model = makeModel()
        seed(model, [
            snap(1, state: .running, actions: [.pause, .cancel, .remove]),
            snap(2, state: .paused, actions: [.resume, .cancel, .remove])
        ])
        model.rowStore.setSelectedJobIDs([jobID(1), jobID(2)], anchor: jobID(1))

        model.clearTableSelection()

        XCTAssertTrue(model.rowStore.selectedJobIDs.isEmpty)
        XCTAssertNil(model.rowStore.selectionAnchorID)
    }

    func test_batchRemoveConfirmsOnceThenRemovesApplicableOnly() async throws {
        let engine = FakeEngine()
        let model = makeModel(engine: engine)
        seed(model, [
            snap(1, state: .queued, actions: [.cancel, .remove]),
            snap(2, state: .cancelled, actions: [.retry, .remove]),
            snap(3, state: .running, actions: [.pause, .cancel, .remove])
        ])
        // 2 cancelled → no confirm needed alone; 1+3 need confirm → one batch confirm.
        model.rowStore.setSelectedJobIDs([jobID(1), jobID(2)], anchor: jobID(1))

        let action = Task { await model.handleBatchAction(.remove) }
        try await pollUntil { model.pendingConfirmation != nil }
        XCTAssertEqual(model.pendingConfirmation?.confirmTitle, "Remove")
        model.resolveConfirmation(true, suppressFutures: false)
        await action.value

        XCTAssertEqual(Set(engine.removedIDs), [jobID(1), jobID(2)])
    }

    func test_batchRemoveRejectedConfirmRemovesNothing() async throws {
        let engine = FakeEngine()
        let model = makeModel(engine: engine)
        seed(model, [
            snap(1, state: .queued, actions: [.cancel, .remove])
        ])
        model.rowStore.setSelectedJobIDs([jobID(1)], anchor: jobID(1))

        let action = Task { await model.handleBatchAction(.remove) }
        try await pollUntil { model.pendingConfirmation != nil }
        model.resolveConfirmation(false, suppressFutures: false)
        await action.value

        XCTAssertEqual(engine.removedIDs, [])
    }

    func test_batchForceStartOnlyWhenExactlyOneEligible() async {
        let engine = FakeEngine()
        let model = makeModel(engine: engine)
        seed(model, [
            snap(1, state: .queued, actions: [.forceStart, .cancel, .remove]),
            snap(2, state: .queued, actions: [.forceStart, .cancel, .remove]),
            snap(3, state: .running, actions: [.pause, .cancel, .remove])
        ])

        model.rowStore.setSelectedJobIDs([jobID(1), jobID(2)], anchor: jobID(1))
        await model.handleBatchAction(.forceStart)
        XCTAssertEqual(engine.forceStartedIDs, [])

        model.rowStore.setSelectedJobIDs([jobID(1)], anchor: jobID(1))
        await model.handleBatchAction(.forceStart)
        XCTAssertEqual(engine.forceStartedIDs, [jobID(1)])
    }

    func test_batchCancelConfirmsOnceThenCancelsApplicable() async throws {
        let engine = FakeEngine()
        let model = makeModel(engine: engine)
        seed(model, [
            snap(1, state: .queued, actions: [.cancel, .remove]),
            snap(2, state: .completed, actions: [.remove]),
            snap(3, state: .running, actions: [.pause, .cancel, .remove])
        ])
        model.rowStore.setSelectedJobIDs([jobID(1), jobID(2), jobID(3)], anchor: jobID(1))

        let action = Task { await model.handleBatchAction(.cancel) }
        try await pollUntil { model.pendingConfirmation != nil }
        model.resolveConfirmation(true, suppressFutures: false)
        await action.value

        XCTAssertEqual(Set(engine.cancelledIDs), [jobID(1), jobID(3)])
    }

    func test_batchPauseAppliesOnlyToEligible() async {
        let engine = FakeEngine()
        let model = makeModel(engine: engine)
        seed(model, [
            snap(1, state: .running, actions: [.pause, .cancel, .remove]),
            snap(2, state: .queued, actions: [.cancel, .remove])
        ])
        model.rowStore.setSelectedJobIDs([jobID(1), jobID(2)], anchor: jobID(1))

        await model.handleBatchAction(.pause)

        XCTAssertEqual(engine.pausedIDs, [jobID(1)])
    }

    private func makeModel(engine: FakeEngine = FakeEngine()) -> AppModel {
        AppModelTestHelpers.makeModel(
            defaults: defaults,
            logDirectory: logDirectory,
            engine: engine
        )
    }

    private func seed(_ model: AppModel, _ jobs: [JobSnapshot]) {
        model.rowStore.apply(.snapshot(QueueSnapshot(
            jobs: jobs,
            revision: 1,
            queueHalt: nil,
            generatedAt: .init(),
            hostRateSummary: [:],
            isOnline: true
        )))
    }

    private func snap(
        _ index: Int,
        state: JobState,
        actions: Set<RowAction>
    ) -> JobSnapshot {
        let url = "https://example.com/videos/\(index)"
        return JobSnapshot(
            id: jobID(index),
            url: url,
            rateHost: RateHost(urlString: url),
            title: "Clip \(index)",
            state: state,
            progress: nil,
            kind: .video(maxHeight: 1080),
            durationSeconds: 10,
            extractor: "youtube",
            addedAt: Date(timeIntervalSince1970: TimeInterval(index)),
            finishedAt: nil,
            destFolder: URL(fileURLWithPath: "/tmp"),
            outputFiles: [],
            sizeBytes: nil,
            actualQuality: nil,
            attempt: 0,
            cooldownUntil: nil,
            playerClientUsed: nil,
            playlistGroupID: nil,
            integrityVerdict: nil,
            availableActions: actions
        )
    }

    private func jobID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
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
