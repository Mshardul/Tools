@testable import GrabberKit
import TestSupport
import XCTest

final class EnginePlaylistGroupTests: XCTestCase {
    private typealias Fix = EngineFixture

    func testUpsertAppearsOnSnapshotWhenChildrenExist() async {
        let persistence = FakeQueuePersisting()
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(
            runner: FakeProcessRunner(),
            probe: probe,
            persistence: persistence
        )
        let groupID = UUID()
        let item = PlaylistSubmitItem(
            request: Fix.request(url: "https://youtube.com/watch?v=a"),
            force: true,
            prefetched: MediaMetadata(
                title: "Clip", durationSeconds: 10, isPlaylist: false,
                sourceURL: "https://youtube.com/watch?v=a", extractor: "youtube"
            ),
            playlistGroupID: groupID,
            playlistIndex: 1
        )
        _ = await engine.submitPlaylistItems([item])
        await engine.upsertPlaylistGroup(PersistedPlaylistGroup(
            id: groupID, title: "Road Trip", sourceURL: "https://example.com/pl", isCollapsed: false
        ))
        let snapshot = await engine.currentSnapshot()
        XCTAssertEqual(snapshot.playlistGroups.map(\.id), [groupID])
        XCTAssertEqual(snapshot.playlistGroups.first?.totalCount, 1)
        XCTAssertEqual(persistence.playlistGroupSaves.last?.map(\.id), [groupID])
    }

    func testCollapseFlipsOnNextSnapshot() async {
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: FakeProcessRunner(), probe: probe)
        let groupID = UUID()
        let item = PlaylistSubmitItem(
            request: Fix.request(url: "https://youtube.com/watch?v=a"),
            force: true,
            prefetched: MediaMetadata(
                title: "Clip", durationSeconds: 10, isPlaylist: false,
                sourceURL: "https://youtube.com/watch?v=a", extractor: "youtube"
            ),
            playlistGroupID: groupID,
            playlistIndex: 1
        )
        _ = await engine.submitPlaylistItems([item])
        await engine.upsertPlaylistGroup(PersistedPlaylistGroup(
            id: groupID, title: "PL", sourceURL: "https://x", isCollapsed: false
        ))
        await engine.setPlaylistGroupCollapsed(id: groupID, true)
        let snapshot = await engine.currentSnapshot()
        XCTAssertEqual(snapshot.playlistGroups.first?.isCollapsed, true)
    }

    func testRemovingLastChildPrunesGroup() async throws {
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let persistence = FakeQueuePersisting()
        let engine = Fix.engine(
            runner: FakeProcessRunner(),
            probe: probe,
            persistence: persistence
        )
        let groupID = UUID()
        let item = PlaylistSubmitItem(
            request: Fix.request(url: "https://youtube.com/watch?v=a"),
            force: true,
            prefetched: MediaMetadata(
                title: "Clip", durationSeconds: 10, isPlaylist: false,
                sourceURL: "https://youtube.com/watch?v=a", extractor: "youtube"
            ),
            playlistGroupID: groupID,
            playlistIndex: 1
        )
        let ids = await engine.submitPlaylistItems([item])
        await engine.upsertPlaylistGroup(PersistedPlaylistGroup(
            id: groupID, title: "PL", sourceURL: "https://x", isCollapsed: false
        ))
        let id = try XCTUnwrap(ids.first)
        await engine.remove(id)
        let snapshot = await engine.currentSnapshot()
        XCTAssertTrue(snapshot.playlistGroups.isEmpty)
        XCTAssertEqual(persistence.playlistGroupSaves.last, [])
    }
}
