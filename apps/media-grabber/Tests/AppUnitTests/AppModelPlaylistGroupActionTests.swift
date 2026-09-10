import Foundation
@testable import GrabberKit
@testable import MediaGrabber
import TestSupport
import XCTest

@MainActor
final class AppModelPlaylistGroupActionTests: XCTestCase {
    private let groupID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    private var defaults = UserDefaults.standard
    private var suiteName = ""
    private var logDirectory: URL!

    override func setUp() async throws {
        suiteName = "mg.groupactions.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        logDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-groupactions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: logDirectory)
    }

    func test_pauseAllPausesOnlyRunningPlaylistChildren() async {
        let engine = FakeEngine()
        let model = makeModel(engine: engine)
        model.playlistGroups = [group()]
        model.rowStore.apply(.snapshot(queueSnapshot([
            snap(1, state: .running, playlistGroupID: groupID),
            snap(2, state: .queued, playlistGroupID: groupID),
            snap(3, state: .running)
        ])))
        model.rowStore.applyGroups(model.playlistGroups)

        await model.handlePlaylistGroupAction(groupID, action: .pauseAll)

        XCTAssertEqual(engine.pausedIDs, [jobID(1)])
    }

    func test_retryFailedRetriesOnlyFailedPlaylistChildren() async {
        let engine = FakeEngine()
        let model = makeModel(engine: engine)
        model.playlistGroups = [group()]
        model.rowStore.apply(.snapshot(queueSnapshot([
            snap(1, state: .failed(.unavailable), playlistGroupID: groupID),
            snap(2, state: .queued, playlistGroupID: groupID),
            snap(3, state: .failed(.private))
        ])))
        model.rowStore.applyGroups(model.playlistGroups)

        await model.handlePlaylistGroupAction(groupID, action: .retryFailed)

        XCTAssertEqual(engine.retriedIDs, [jobID(1)])
    }

    func test_cancelAllConfirmsThenCancelsCancellablePlaylistChildren() async throws {
        let engine = FakeEngine()
        let model = makeModel(engine: engine)
        model.playlistGroups = [group()]
        model.rowStore.apply(.snapshot(queueSnapshot([
            snap(1, state: .queued, playlistGroupID: groupID),
            snap(2, state: .paused, playlistGroupID: groupID),
            snap(3, state: .probing, playlistGroupID: groupID),
            snap(4, state: .running, playlistGroupID: groupID),
            snap(5, state: .completed, playlistGroupID: groupID),
            snap(6, state: .failed(.unavailable), playlistGroupID: groupID)
        ])))
        model.rowStore.applyGroups(model.playlistGroups)

        let action = Task {
            await model.handlePlaylistGroupAction(groupID, action: .cancelAll)
        }
        try await pollUntil { model.pendingConfirmation != nil }
        XCTAssertEqual(model.pendingConfirmation?.suppressionKey, "playlist-cancel-all")
        model.resolveConfirmation(true, suppressFutures: false)
        await action.value

        XCTAssertEqual(engine.cancelledIDs, [jobID(1), jobID(2), jobID(3), jobID(4)])
    }

    func test_cancelAllDoesNothingWhenConfirmationIsRejected() async throws {
        let engine = FakeEngine()
        let model = makeModel(engine: engine)
        model.playlistGroups = [group()]
        model.rowStore.apply(.snapshot(queueSnapshot([
            snap(1, state: .queued, playlistGroupID: groupID)
        ])))
        model.rowStore.applyGroups(model.playlistGroups)

        let action = Task {
            await model.handlePlaylistGroupAction(groupID, action: .cancelAll)
        }
        try await pollUntil { model.pendingConfirmation != nil }
        model.resolveConfirmation(false, suppressFutures: false)
        await action.value

        XCTAssertEqual(engine.cancelledIDs, [])
    }

    func test_collapseUpdatesRowStoreRegistryAndPersistence() {
        let persistence = FakeQueuePersisting()
        let model = makeModel(persistence: persistence)
        model.playlistGroups = [group()]
        model.rowStore.apply(.snapshot(queueSnapshot([
            snap(1, state: .queued, playlistGroupID: groupID)
        ])))
        model.rowStore.applyGroups(model.playlistGroups)

        model.setPlaylistGroupCollapsed(id: groupID, true)

        XCTAssertTrue(model.rowStore.groups.first?.isCollapsed == true)
        XCTAssertTrue(model.playlistGroups.first?.isCollapsed == true)
        XCTAssertEqual(persistence.playlistGroupSaves.last?.first?.isCollapsed, true)
    }

    func test_removeLastPlaylistChildDropsRegistryRow() async {
        let engine = FakeEngine()
        let persistence = FakeQueuePersisting()
        let model = makeModel(engine: engine, persistence: persistence)
        model.playlistGroups = [group()]
        model.rowStore.apply(.snapshot(queueSnapshot([
            snap(1, state: .queued, playlistGroupID: groupID)
        ])))
        model.rowStore.applyGroups(model.playlistGroups)

        await model.handleRowAction(jobID(1), action: .remove)

        XCTAssertEqual(engine.removedIDs, [jobID(1)])
        XCTAssertTrue(model.playlistGroups.isEmpty)
        XCTAssertEqual(persistence.playlistGroupSaves.last, [])
    }

    private func makeModel(
        engine: FakeEngine = FakeEngine(),
        persistence: FakeQueuePersisting? = nil
    ) -> AppModel {
        AppModelTestHelpers.makeModel(
            defaults: defaults,
            logDirectory: logDirectory,
            engine: engine,
            persistence: persistence
        )
    }

    private func group() -> PersistedPlaylistGroup {
        PersistedPlaylistGroup(
            id: groupID,
            title: "Road Trip",
            sourceURL: "https://example.com/playlist",
            isCollapsed: false
        )
    }

    private func queueSnapshot(_ jobs: [JobSnapshot]) -> QueueSnapshot {
        QueueSnapshot(
            jobs: jobs,
            revision: 1,
            queueHalt: nil,
            generatedAt: .init(),
            hostRateSummary: [:],
            isOnline: true
        )
    }

    private func snap(
        _ index: Int,
        state: JobState,
        playlistGroupID: UUID? = nil
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
            playlistGroupID: playlistGroupID,
            playlistIndex: index,
            integrityVerdict: nil,
            availableActions: []
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
