@testable import GrabberKit
@testable import MediaGrabber
import XCTest

@MainActor
final class RowStoreTests: XCTestCase {
    private var revision: UInt64 = 0

    override func setUp() {
        super.setUp()
        revision = 0
    }

    private func snap(
        _ index: Int,
        state: JobState = .queued,
        title: String? = "Clip \(0)",
        extractor: String? = nil,
        progressFraction: Double? = nil,
        kind: DownloadKind = .video(maxHeight: 1080),
        durationSeconds: Int? = nil,
        sizeBytes: Int64? = nil
    ) -> JobSnapshot {
        JobSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")!,
            url: "https://archive.org/details/\(index)",
            title: title, state: state,
            progress: progressFraction.map {
                DownloadProgress(
                    fraction: $0,
                    speedBytesPerSec: 1000,
                    etaSeconds: 5,
                    downloadedBytes: 0
                )
            },
            kind: kind, durationSeconds: durationSeconds, extractor: extractor,
            addedAt: Date(timeIntervalSince1970: TimeInterval(index)), finishedAt: nil,
            destFolder: URL(fileURLWithPath: "/tmp"), outputFiles: [], sizeBytes: sizeBytes,
            actualQuality: nil, attempt: 0, cooldownUntil: nil, playerClientUsed: nil,
            playlistGroupID: nil, integrityVerdict: nil, availableActions: []
        )
    }

    private func queueSnapshot(_ jobs: [JobSnapshot]) -> QueueSnapshot {
        revision += 1
        return QueueSnapshot(jobs: jobs, revision: revision, queueHalt: nil, generatedAt: .init())
    }

    private func progressEvent(_ id: Int, fraction: Double) -> QueueEvent {
        revision += 1
        let progress = DownloadProgress(
            fraction: fraction, speedBytesPerSec: 2000, etaSeconds: 3, downloadedBytes: 0
        )
        let key = UUID(uuidString: "00000000-0000-0000-0000-00000000000\(id)")!
        return .progress([key: progress], revision: revision)
    }

    func test_snapshotSequence_stableIdentities_onlyChangedFieldsMutate() {
        let store = RowStore()
        store.apply(.snapshot(queueSnapshot([snap(1, title: "A"), snap(2, title: "B")])))
        let first = store.rows

        store.apply(.snapshot(queueSnapshot([snap(1, title: "A2"), snap(2, title: "B")])))

        XCTAssertTrue(first[0] === store.rows[0])
        XCTAssertTrue(first[1] === store.rows[1])
        XCTAssertEqual(store.rows[0].snapshot.title, "A2")
        XCTAssertEqual(store.rows[1].recomputeCount, 1, "unchanged row not recomputed")
        XCTAssertEqual(store.rows[0].recomputeCount, 2)
    }

    func test_progressEvent_patchesProgress_keepsIdentityAndOrder() {
        let store = RowStore()
        store.apply(.snapshot(queueSnapshot([
            snap(1, state: .running), snap(2, state: .running)
        ])))
        let before = store.visibleRows.map(\.id)

        store.apply(progressEvent(2, fraction: 0.9))

        XCTAssertEqual(store.visibleRows.map(\.id), before)
        XCTAssertEqual(store.rows[1].snapshot.progress?.fraction, 0.9)
    }

    func test_progressSortActive_progressEventReorders() {
        var config = ColumnConfig.default
        config.sortColumn = .progress
        config.sortDirection = .descending
        let store = RowStore(columnConfig: config)
        store.apply(.snapshot(queueSnapshot([
            snap(1, state: .running, progressFraction: 0.1),
            snap(2, state: .running, progressFraction: 0.2)
        ])))
        XCTAssertEqual(store.visibleRows.map { String($0.id.uuidString.suffix(1)) }, ["2", "1"])

        store.apply(progressEvent(1, fraction: 0.95))
        XCTAssertEqual(store.visibleRows.map { String($0.id.uuidString.suffix(1)) }, ["1", "2"])
    }

    func test_chipFilter_plusColumnFilter_plusSort_composeInVisibleRows() {
        var config = ColumnConfig.default
        config.sortColumn = .addedAt
        config.sortDirection = .ascending
        config.columnFilters = [.type: ["Video"]]
        let store = RowStore(columnConfig: config)
        store.apply(.snapshot(queueSnapshot([
            snap(1, state: .running, kind: .video(maxHeight: 720)),
            snap(2, state: .completed, kind: .audio(format: .mp3)),
            snap(3, state: .running, kind: .video(maxHeight: 1080))
        ])))
        store.activeChip = .downloading

        XCTAssertEqual(store.visibleRows.map { String($0.id.uuidString.suffix(1)) }, ["1", "3"])
    }

    func test_chipCounts_correct() {
        let store = RowStore()
        store.apply(.snapshot(queueSnapshot([
            snap(1, state: .running),
            snap(2, state: .completed),
            snap(3, state: .failed(.networkDown)),
            snap(4, state: .cooldown(until: .init()))
        ])))

        XCTAssertEqual(store.chipCounts.all, 4)
        XCTAssertEqual(store.chipCounts.downloading, 1)
        XCTAssertEqual(store.chipCounts.done, 1)
        XCTAssertEqual(store.chipCounts.needsAttention, 2)
    }

    func test_resync_rebuildsFromSnapshot() {
        let store = RowStore()
        store.apply(.snapshot(queueSnapshot([snap(1), snap(2), snap(3)])))
        XCTAssertEqual(store.rows.count, 3)

        store.resync(queueSnapshot([snap(9)]))
        XCTAssertEqual(store.rows.map { String($0.id.uuidString.suffix(1)) }, ["9"])
    }

    func test_siteLabel_emDashPreProbe_extractorLabelAfter() {
        let store = RowStore()
        store.apply(.snapshot(queueSnapshot([snap(1, extractor: nil)])))
        XCTAssertEqual(store.rows[0].siteLabel, "—")

        store.apply(.snapshot(queueSnapshot([snap(1, extractor: "youtube")])))
        XCTAssertEqual(store.rows[0].siteLabel, "YouTube")
    }

    func test_queueBadge_isOneBasedPositionForQueuedRows() {
        let store = RowStore()
        store.apply(.snapshot(queueSnapshot([
            snap(1, state: .running),
            snap(2, state: .queued),
            snap(3, state: .queued)
        ])))

        XCTAssertNil(store.rows[0].queueBadge)
        XCTAssertEqual(store.rows[1].queueBadge, "#1")
        XCTAssertEqual(store.rows[2].queueBadge, "#2")
    }
}
