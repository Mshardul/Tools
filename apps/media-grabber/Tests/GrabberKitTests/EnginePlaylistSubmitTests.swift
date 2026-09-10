@testable import GrabberKit
import TestSupport
import XCTest

final class EnginePlaylistSubmitTests: XCTestCase {
    private typealias Fix = EngineFixture

    private func playlistDump() -> PlaylistDump {
        PlaylistDump(
            title: "Playlist",
            uploader: "Uploader",
            extractor: "youtube:tab",
            sourceURL: "https://youtube.com/playlist?list=abc",
            entries: [
                PlaylistEntry(
                    watchURL: "https://youtube.com/watch?v=one",
                    title: "One",
                    durationSeconds: 11,
                    thumbnailURL: nil,
                    extractor: "Youtube",
                    playlistIndex: 1
                )
            ]
        )
    }

    private func playlistProbe(_ result: FakeMetadataProbe.PlaylistOutcome) -> FakeMetadataProbe {
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        probe.playlistResult(result)
        return probe
    }

    private func metadata(title: String) -> MediaMetadata {
        MediaMetadata(
            title: title,
            durationSeconds: 12,
            isPlaylist: false,
            sourceURL: "",
            extractor: "youtube"
        )
    }

    private func item(
        url: String,
        groupID: UUID,
        index: Int,
        force: Bool = false,
        destFolder: URL = Fix.scratchDestFolder(),
        title: String = "Clip"
    ) -> PlaylistSubmitItem {
        PlaylistSubmitItem(
            request: Fix.request(url: url, destFolder: destFolder),
            force: force,
            prefetched: metadata(title: title),
            playlistGroupID: groupID,
            playlistIndex: index
        )
    }

    func test_previewPlaylistSuccessReturnsDumpAndCreatesNoJob() async {
        let dump = playlistDump()
        let engine = Fix.engine(
            runner: FakeProcessRunner(),
            probe: playlistProbe(.success(dump))
        )

        let result = await engine.previewPlaylist("https://youtube.com/playlist?list=abc")

        XCTAssertEqual(result, .success(dump))
        let snapshot = await engine.currentSnapshot()
        XCTAssertTrue(snapshot.jobs.isEmpty)
    }

    func test_previewPlaylistNetworkDownReturnsNetworkError() async {
        let net = FakeNetworkMonitor(startOnline: true)
        let engine = Fix.engine(
            runner: FakeProcessRunner(),
            probe: playlistProbe(.success(playlistDump())),
            networkMonitor: net
        )
        let collector = EventCollector(engine.events)
        net.goOffline()
        let halted = await waitForHalt(collector, .networkDown)
        XCTAssertTrue(halted)

        let result = await engine.previewPlaylist("https://youtube.com/playlist?list=abc")

        XCTAssertEqual(result, .failure(.network))
    }

    func test_previewPlaylistHostBlockedDuringCooldown() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1000))
        let runner = FakeProcessRunner()
        runner.script(
            .stderr("ERROR: HTTP Error 429: Too Many Requests", exitCode: 1),
            forPathEndingIn: "yt-dlp"
        )
        let engine = Fix.engine(
            runner: runner,
            probe: playlistProbe(.success(playlistDump())),
            cap: 1,
            clock: clock
        )
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=a"))
        let cooled = await collector.waitForState(id) {
            if case .cooldown = $0 {
                return true
            }
            return false
        }
        XCTAssertTrue(cooled)

        let result = await engine.previewPlaylist("https://youtube.com/playlist?list=abc")

        XCTAssertEqual(result, .failure(.hostBlocked))
    }

    func test_submitPlaylistItemsEnqueuesBatchWithPrefetchAndOneRevision() async {
        let engine = Fix.engine(
            runner: FakeProcessRunner(),
            probe: FakeMetadataProbe(),
            cap: 0
        )
        let groupID = UUID()
        let before = await engine.currentSnapshot().revision

        let ids = await engine.submitPlaylistItems([
            item(url: "https://youtube.com/watch?v=one", groupID: groupID, index: 1, title: "One"),
            item(url: "https://youtube.com/watch?v=two", groupID: groupID, index: 2, title: "Two")
        ])

        let snapshot = await engine.currentSnapshot()
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(snapshot.revision, before + 1)
        XCTAssertEqual(snapshot.jobs.map(\.id), ids)
        XCTAssertEqual(snapshot.jobs.map(\.playlistGroupID), [groupID, groupID])
        XCTAssertEqual(snapshot.jobs.map(\.playlistIndex), [1, 2])
        XCTAssertEqual(snapshot.jobs.map(\.title), ["One", "Two"])
        XCTAssertEqual(snapshot.jobs.map(\.extractor), ["youtube", "youtube"])
        XCTAssertEqual(snapshot.jobs.map(\.durationSeconds), [12, 12])
        XCTAssertEqual(snapshot.jobs.map(\.state), [.queued, .queued])
    }

    func test_submitPlaylistItemsForceTrueAllowsDuplicateURL() async {
        let engine = Fix.engine(
            runner: FakeProcessRunner(),
            probe: FakeMetadataProbe(),
            cap: 0
        )
        let groupID = UUID()
        let url = "https://youtube.com/watch?v=same"
        let destFolder = Fix.scratchDestFolder()

        let ids = await engine.submitPlaylistItems([
            item(
                url: url,
                groupID: groupID,
                index: 1,
                force: true,
                destFolder: destFolder,
                title: "One"
            ),
            item(
                url: url,
                groupID: groupID,
                index: 2,
                force: true,
                destFolder: destFolder,
                title: "Two"
            )
        ])

        let snapshot = await engine.currentSnapshot()
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(snapshot.jobs.map(\.url), [url, url])
    }

    func test_submitPlaylistItemsSkipsDuplicateInBatchWhenForceFalse() async {
        let engine = Fix.engine(
            runner: FakeProcessRunner(),
            probe: FakeMetadataProbe(),
            cap: 0
        )
        let groupID = UUID()
        let duplicate = "https://youtube.com/watch?v=same"
        let unique = "https://youtube.com/watch?v=unique"
        let destFolder = Fix.scratchDestFolder()

        let ids = await engine.submitPlaylistItems([
            item(url: duplicate, groupID: groupID, index: 1, destFolder: destFolder, title: "One"),
            item(url: duplicate, groupID: groupID, index: 2, destFolder: destFolder, title: "Two"),
            item(url: unique, groupID: groupID, index: 3, title: "Three")
        ])

        let snapshot = await engine.currentSnapshot()
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(snapshot.jobs.map(\.id), ids)
        XCTAssertEqual(snapshot.jobs.map(\.url), [duplicate, unique])
        XCTAssertEqual(snapshot.jobs.map(\.playlistIndex), [1, 3])
    }

    private func waitForHalt(_ collector: EventCollector, _ reason: QueueHaltReason) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if collector.latestSnapshot()?.queueHalt == reason {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}
