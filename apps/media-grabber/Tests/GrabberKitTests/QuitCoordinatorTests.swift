@testable import GrabberKit
import TestSupport
import XCTest

final class QuitCoordinatorTests: XCTestCase {
    private func makeCoordinator(
        engine: FakeEngine,
        persistence: FakeQueuePersisting = FakeQueuePersisting(),
        confirmer: FakeConfirmer = FakeConfirmer(answering: true)
    ) -> QuitCoordinator {
        QuitCoordinator(engine: engine, persistence: persistence, confirmer: confirmer)
    }

    func test_activeJobs_promptsConfirm_cancelStopsQuit() async {
        let engine = FakeEngine()
        engine.setHasActiveJobs(true)
        let confirmer = FakeConfirmer(answering: false)
        let coordinator = makeCoordinator(engine: engine, confirmer: confirmer)

        let shouldQuit = await coordinator.requestTerminate()

        XCTAssertFalse(shouldQuit)
        XCTAssertFalse(engine.shutdownCalled)
        XCTAssertEqual(confirmer.seenRequests.count, 1)
    }

    func test_activeJobs_confirmProceeds_flushThenShutdownThenTrue() async {
        let engine = FakeEngine()
        engine.setHasActiveJobs(true)
        let persistence = FakeQueuePersisting()
        let coordinator = makeCoordinator(engine: engine, persistence: persistence)

        let shouldQuit = await coordinator.requestTerminate()

        XCTAssertTrue(shouldQuit)
        XCTAssertEqual(persistence.flushCount, 1)
        XCTAssertTrue(engine.shutdownCalled)
    }

    func test_queueHaltNonNil_promptsEvenWithNoActiveJobs() async {
        let engine = FakeEngine()
        engine.setSnapshot(QueueSnapshot(
            jobs: [],
            revision: 1,
            queueHalt: .depMissing,
            generatedAt: .init()
        ))
        let confirmer = FakeConfirmer(answering: false)
        let coordinator = makeCoordinator(engine: engine, confirmer: confirmer)

        let shouldQuit = await coordinator.requestTerminate()

        XCTAssertFalse(shouldQuit)
        XCTAssertEqual(confirmer.seenRequests.count, 1)
        XCTAssertTrue(confirmer.seenRequests[0].message.contains("yt-dlp"))
    }

    func test_purelyQueuedNoHalt_noPrompt_flushShutdownTrue() async {
        let engine = FakeEngine()
        let persistence = FakeQueuePersisting()
        let confirmer = FakeConfirmer(answering: false)
        let coordinator = makeCoordinator(
            engine: engine,
            persistence: persistence,
            confirmer: confirmer
        )

        let shouldQuit = await coordinator.requestTerminate()

        XCTAssertTrue(shouldQuit)
        XCTAssertTrue(confirmer.seenRequests.isEmpty)
        XCTAssertEqual(persistence.flushCount, 1)
        XCTAssertTrue(engine.shutdownCalled)
    }

    func test_flushFailure_doesNotBlockQuit() async {
        let engine = FakeEngine()
        let persistence = FakeQueuePersisting()
        let coordinator = makeCoordinator(engine: engine, persistence: persistence)

        let shouldQuit = await coordinator.requestTerminate()

        XCTAssertTrue(shouldQuit)
        XCTAssertEqual(persistence.flushCount, 1)
        XCTAssertTrue(engine.shutdownCalled)
    }
}

private final class FakeEngine: DownloadEngineProtocol, @unchecked Sendable {
    private let box = LockedBox(State())
    private let continuation: AsyncStream<QueueEvent>.Continuation
    let events: AsyncStream<QueueEvent>

    private struct State {
        var hasActive = false
        var snapshot = QueueSnapshot(jobs: [], revision: 0, queueHalt: nil, generatedAt: .init())
        var shutdownCalled = false
    }

    init() {
        let (stream, continuation) = AsyncStream<QueueEvent>.makeStream()
        events = stream
        self.continuation = continuation
    }

    var shutdownCalled: Bool {
        box.read { $0.shutdownCalled }
    }

    func setHasActiveJobs(_ value: Bool) {
        box.mutate { $0.hasActive = value }
    }

    func setSnapshot(_ snapshot: QueueSnapshot) {
        box.mutate { $0.snapshot = snapshot }
    }

    func currentSnapshot() async -> QueueSnapshot {
        box.read { $0.snapshot }
    }

    func hasActiveJobs() async -> Bool {
        box.read { $0.hasActive }
    }

    func submit(
        _: DownloadRequest,
        force _: Bool,
        prefetchedMetadata _: MediaMetadata?
    ) async -> SubmitResult {
        .queued(UUID())
    }

    func restore(active _: [PersistedJob], history _: [PersistedJob]) async {}
    func revalidate() async {}
    func pause(_: UUID) async {}
    func resume(_: UUID) async {}
    func cancel(_: UUID) async {}
    func remove(_: UUID) async {}
    func forceStart(_: UUID) async {}

    func shutdown() async {
        box.mutate { $0.shutdownCalled = true }
    }
}
