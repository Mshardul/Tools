@testable import GrabberKit
@testable import MediaGrabber
import TestSupport
import XCTest

@MainActor
final class AppModelRowReorderTests: XCTestCase {
    private var defaults = UserDefaults.standard
    private var suiteName = ""
    private var logDirectory: URL!
    private var revision: UInt64 = 0

    override func setUp() async throws {
        suiteName = "mg.reorder.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        logDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-reorder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        revision = 0
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: logDirectory)
    }

    private func makeModel() -> AppModel {
        AppModelTestHelpers.makeModel(defaults: defaults, logDirectory: logDirectory)
    }

    private func seedThreeJobs(_ model: AppModel) {
        model.rowStore.apply(.snapshot(queueSnapshot([snap(1), snap(2), snap(3)])))
    }

    func test_handleRowReorder_whenSorted_cancel_leavesSortAndOrder() async throws {
        let model = makeModel()
        XCTAssertEqual(model.columnConfig.sortColumn, .addedAt)
        seedThreeJobs(model)
        let before = model.rowStore.visibleRows.map(\.id)

        let task = Task { await model.handleRowReorder(from: 0, to: 2) }
        try await pollUntil { model.pendingConfirmation != nil }
        XCTAssertEqual(model.pendingConfirmation?.title, "Clear sorting?")
        model.resolveConfirmation(false, suppressFutures: false)
        await task.value

        XCTAssertEqual(model.columnConfig.sortColumn, .addedAt)
        XCTAssertNil(model.rowStore.manualOrder)
        XCTAssertEqual(model.rowStore.visibleRows.map(\.id), before)
    }

    func test_handleRowReorder_whenSorted_proceed_clearsSortAndMoves() async throws {
        let model = makeModel()
        seedThreeJobs(model)
        let ids = model.rowStore.rows.map(\.id)

        let task = Task { await model.handleRowReorder(from: 0, to: 2) }
        try await pollUntil { model.pendingConfirmation != nil }
        model.resolveConfirmation(true, suppressFutures: false)
        await task.value

        XCTAssertNil(model.columnConfig.sortColumn)
        XCTAssertNotNil(model.rowStore.manualOrder)
        XCTAssertEqual(model.rowStore.visibleRows.map(\.id), [ids[1], ids[0], ids[2]])
    }

    func test_handleRowReorder_whenSortNil_movesWithoutConfirm() async {
        let model = makeModel()
        var config = model.columnConfig
        config.sortColumn = nil
        config.sortDirection = nil
        model.columnConfig = config
        seedThreeJobs(model)
        let ids = model.rowStore.rows.map(\.id)

        await model.handleRowReorder(from: 0, to: 2)

        XCTAssertNil(model.pendingConfirmation)
        XCTAssertEqual(model.rowStore.visibleRows.map(\.id), [ids[1], ids[0], ids[2]])
    }

    private func snap(_ index: Int) -> JobSnapshot {
        let url = "https://archive.org/details/\(index)"
        return JobSnapshot(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
            url: url,
            rateHost: RateHost(urlString: url),
            title: "Clip \(index)",
            state: .queued,
            progress: nil,
            kind: .video(maxHeight: 1080),
            durationSeconds: nil,
            extractor: nil,
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
            playlistIndex: nil,
            integrityVerdict: nil,
            availableActions: []
        )
    }

    private func queueSnapshot(_ jobs: [JobSnapshot]) -> QueueSnapshot {
        revision += 1
        return QueueSnapshot(
            jobs: jobs,
            revision: revision,
            queueHalt: nil,
            generatedAt: .init(),
            hostRateSummary: [:],
            isOnline: true
        )
    }

    private func pollUntil(
        timeout: TimeInterval = 2,
        _ predicate: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("timed out waiting for condition")
    }
}
