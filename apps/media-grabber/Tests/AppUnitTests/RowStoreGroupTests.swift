@testable import GrabberKit
@testable import MediaGrabber
import XCTest

@MainActor
final class RowStoreGroupTests: XCTestCase {
    private let groupID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private var revision: UInt64 = 0

    override func setUp() {
        super.setUp()
        revision = 0
    }

    func test_defaultAddedAtSortInterleavesUngroupedBeforeGroupAndOrdersChildrenByPlaylistIndex() {
        let store = RowStore()
        store.applyGroups([group(title: "Road Trip")])
        store.apply(.snapshot(queueSnapshot([
            snap(1, title: "Second", playlistGroupID: groupID, playlistIndex: 2, addedAt: 20),
            snap(2, title: "First", playlistGroupID: groupID, playlistIndex: 1, addedAt: 10),
            snap(3, title: "Newest", addedAt: 30)
        ])))

        XCTAssertEqual(store.visibleRows.map(\.snapshot.title), ["Newest", "Second", "First"])
        XCTAssertEqual(visibleItemTitles(store.visibleItems), [
            "Newest", "Road Trip", "First", "Second"
        ])
        XCTAssertEqual(store.groups.first?.addedAt, Date(timeIntervalSince1970: 10))
    }

    func test_doneChipShowsMatchingChildAndGroupRollupIncludesAllMembers() {
        let store = RowStore()
        store.applyGroups([group()])
        store.apply(.snapshot(queueSnapshot([
            snap(1, state: .queued, playlistGroupID: groupID, playlistIndex: 1),
            snap(2, state: .completed, playlistGroupID: groupID, playlistIndex: 2)
        ])))
        store.activeChip = .done

        XCTAssertEqual(visibleItemIDs(store.visibleItems), [
            "g-\(groupID)",
            "j-00000000-0000-0000-0000-000000000002"
        ])
        XCTAssertEqual(store.groups.first?.totalCount, 2)
        XCTAssertEqual(store.groups.first?.completedCount, 1)
        XCTAssertEqual(store.groups.first?.rollupFraction ?? -1, 0.5, accuracy: 0.0001)
    }

    func test_progressTicksOnlyChangeGroupWhenCrossingTenPercentBucket() {
        let store = RowStore()
        store.applyGroups([group()])
        store.apply(.snapshot(queueSnapshot([
            snap(
                1,
                state: .running,
                progressFraction: 0.14,
                playlistGroupID: groupID,
                playlistIndex: 1
            ),
            snap(2, playlistGroupID: groupID, playlistIndex: 2)
        ])))
        let firstGroups = store.groups
        XCTAssertEqual(firstGroups.first?.rollupFraction ?? -1, 0.05, accuracy: 0.0001)

        store.apply(progressEvent(1, fraction: 0.16))
        XCTAssertEqual(store.groups, firstGroups)

        store.apply(progressEvent(1, fraction: 0.24))
        XCTAssertEqual(store.groups.first?.rollupFraction ?? -1, 0.1, accuracy: 0.0001)
    }

    func test_collapsedGroupShowsHeaderOnly() {
        let store = RowStore()
        store.applyGroups([group()])
        store.apply(.snapshot(queueSnapshot([
            snap(1, playlistGroupID: groupID, playlistIndex: 1),
            snap(2, playlistGroupID: groupID, playlistIndex: 2)
        ])))

        store.setCollapsed(id: groupID, true)

        XCTAssertEqual(visibleItemIDs(store.visibleItems), ["g-\(groupID)"])
        XCTAssertTrue(store.groups.first?.isCollapsed == true)
    }

    private func snap(
        _ index: Int,
        state: JobState = .queued,
        title: String? = nil,
        extractor: String? = "youtube",
        progressFraction: Double? = nil,
        playlistGroupID: UUID? = nil,
        playlistIndex: Int? = nil,
        addedAt: TimeInterval? = nil,
        finishedAt: Date? = nil,
        sizeBytes: Int64? = nil,
        durationSeconds: Int? = nil
    ) -> JobSnapshot {
        let url = "https://example.com/videos/\(index)"
        return JobSnapshot(
            id: jobID(index),
            url: url,
            rateHost: RateHost(urlString: url),
            title: title ?? "Clip \(index)",
            state: state,
            progress: progressFraction.map {
                DownloadProgress(
                    fraction: $0,
                    speedBytesPerSec: 1000,
                    etaSeconds: 5,
                    downloadedBytes: 0
                )
            },
            kind: .video(maxHeight: 1080),
            durationSeconds: durationSeconds,
            extractor: extractor,
            addedAt: Date(timeIntervalSince1970: addedAt ?? TimeInterval(index)),
            finishedAt: finishedAt,
            destFolder: URL(fileURLWithPath: "/tmp"),
            outputFiles: [],
            sizeBytes: sizeBytes,
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

    private func progressEvent(_ index: Int, fraction: Double) -> QueueEvent {
        revision += 1
        let progress = DownloadProgress(
            fraction: fraction,
            speedBytesPerSec: 1000,
            etaSeconds: 5,
            downloadedBytes: 0
        )
        return .progress([jobID(index): progress], revision: revision)
    }

    private func jobID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
    }

    private func visibleItemIDs(_ items: [VisibleItem]) -> [String] {
        items.map(\.id)
    }

    private func visibleItemTitles(_ items: [VisibleItem]) -> [String] {
        items.map { item in
            switch item {
            case let .header(group):
                group.title
            case let .child(row):
                row.snapshot.title ?? ""
            }
        }
    }
}
