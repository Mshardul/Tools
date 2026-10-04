@testable import GrabberKit
@testable import MediaGrabber
import XCTest

@MainActor
final class RowStoreManualOrderTests: XCTestCase {
    private let groupID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private var revision: UInt64 = 0

    override func setUp() {
        super.setUp()
        revision = 0
    }

    func test_setManualOrder_reordersVisibleChildrenWhenSortNil() {
        var config = ColumnConfig.default
        config.sortColumn = nil
        config.sortDirection = nil
        let store = RowStore(columnConfig: config)
        store.apply(.snapshot(queueSnapshot([snap(1), snap(2), snap(3)])))
        let ids = store.rows.map(\.id)

        store.setManualOrder([ids[2], ids[0], ids[1]])

        XCTAssertEqual(store.visibleRows.map(\.id), [ids[2], ids[0], ids[1]])
        XCTAssertEqual(visibleChildIDs(store.visibleItems), [ids[2], ids[0], ids[1]])
    }

    func test_setColumnConfig_withSort_clearsManualOrder() {
        var config = ColumnConfig.default
        config.sortColumn = nil
        config.sortDirection = nil
        let store = RowStore(columnConfig: config)
        store.apply(.snapshot(queueSnapshot([snap(1), snap(2)])))
        let ids = store.rows.map(\.id)
        store.setManualOrder([ids[1], ids[0]])
        XCTAssertNotNil(store.manualOrder)

        var sorted = config
        sorted.sortColumn = .addedAt
        sorted.sortDirection = .ascending
        store.setColumnConfig(sorted)

        XCTAssertNil(store.manualOrder)
    }

    func test_moveVisibleItem_swapsUngroupedChildren() {
        var config = ColumnConfig.default
        config.sortColumn = nil
        config.sortDirection = nil
        let store = RowStore(columnConfig: config)
        store.apply(.snapshot(queueSnapshot([snap(1), snap(2), snap(3)])))
        let ids = store.rows.map(\.id)

        XCTAssertTrue(store.moveVisibleItem(from: 0, to: 2))
        XCTAssertEqual(store.visibleRows.map(\.id), [ids[1], ids[0], ids[2]])
    }

    func test_moveVisibleItem_refusesHeaderSource() {
        var config = ColumnConfig.default
        config.sortColumn = nil
        config.sortDirection = nil
        let store = RowStore(columnConfig: config)
        store.applyGroups([group()])
        store.apply(.snapshot(queueSnapshot([
            snap(1, playlistGroupID: groupID, playlistIndex: 1),
            snap(2, playlistGroupID: groupID, playlistIndex: 2)
        ])))
        let before = store.visibleItems.map(\.id)

        XCTAssertFalse(store.moveVisibleItem(from: 0, to: 1))
        XCTAssertEqual(store.visibleItems.map(\.id), before)
        XCTAssertNil(store.manualOrder)
    }

    func test_newJob_appendsToEndOfManualOrder() {
        var config = ColumnConfig.default
        config.sortColumn = nil
        config.sortDirection = nil
        let store = RowStore(columnConfig: config)
        store.apply(.snapshot(queueSnapshot([snap(1), snap(2)])))
        let ids = store.rows.map(\.id)
        store.setManualOrder([ids[1], ids[0]])

        store.apply(.snapshot(queueSnapshot([snap(1), snap(2), snap(3)])))

        let id3 = jobID(3)
        XCTAssertEqual(store.manualOrder?.last, id3)
        XCTAssertEqual(store.visibleRows.last?.id, id3)
    }

    private func snap(
        _ index: Int,
        state: JobState = .queued,
        playlistGroupID: UUID? = nil,
        playlistIndex: Int? = nil
    ) -> JobSnapshot {
        let url = "https://archive.org/details/\(index)"
        return JobSnapshot(
            id: jobID(index),
            url: url,
            rateHost: RateHost(urlString: url),
            title: "Clip \(index)",
            state: state,
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
            playlistGroupID: playlistGroupID,
            playlistIndex: playlistIndex,
            integrityVerdict: nil,
            availableActions: []
        )
    }

    private func group(title: String = "Playlist") -> PersistedPlaylistGroup {
        PersistedPlaylistGroup(
            id: groupID,
            title: title,
            sourceURL: "https://example.com/playlist",
            isCollapsed: false
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

    private func jobID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
    }

    private func visibleChildIDs(_ items: [VisibleItem]) -> [UUID] {
        items.compactMap { item in
            if case let .child(row) = item {
                return row.id
            }
            return nil
        }
    }
}
