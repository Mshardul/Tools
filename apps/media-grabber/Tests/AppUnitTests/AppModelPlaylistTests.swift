import Foundation
@testable import GrabberKit
@testable import MediaGrabber
import TestSupport
import XCTest

@MainActor
final class AppModelPlaylistTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard
    private var logDirectory: URL!

    override func setUp() async throws {
        suiteName = "mg.appmodel.playlist.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        logDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-appmodel-playlist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: logDirectory)
    }

    func test_resolvePasted_unsupportedPlaylistLinkDoesNotProbe() async {
        let engine = FakeEngine()
        let model = makeModel(engine: engine)

        await model.resolvePasted("https://www.youtube.com/playlist?list=WL")

        XCTAssertEqual(model.probeError, AppModelDialogs.unsupportedPlaylistLink)
        XCTAssertNil(model.resolved)
        XCTAssertEqual(engine.previewedURLs, [])
        XCTAssertEqual(engine.previewPlaylistURLs, [])
    }

    func test_resolvePasted_playlistPresentsPicker() async {
        let engine = FakeEngine()
        let dump = Self.dump()
        engine.stubPreviewPlaylist(.success(dump))
        let model = makeModel(engine: engine)

        await model.resolvePasted(dump.sourceURL)

        XCTAssertEqual(engine.previewPlaylistURLs, [dump.sourceURL])
        XCTAssertEqual(engine.previewedURLs, [])
        XCTAssertTrue(model.isPlaylistPickerPresented)
        guard case let .playlist(resolvedDump) = model.resolved else {
            XCTFail("Expected playlist resolution")
            return
        }
        XCTAssertEqual(resolvedDump, dump)
    }

    func test_resolvePasted_singleVideoClearsPlaylistPresentation() async {
        let engine = FakeEngine()
        let dump = Self.dump()
        let video = AppModelTestHelpers.meta(title: "Solo", url: "https://archive.org/details/solo")
        engine.stubPreviewPlaylist(.success(dump))
        engine.stubPreview(.success(video))
        let model = makeModel(engine: engine)

        await model.resolvePasted(dump.sourceURL)
        await model.resolvePasted(video.sourceURL)

        XCTAssertFalse(model.isPlaylistPickerPresented)
        guard case let .video(resolvedVideo) = model.resolved else {
            XCTFail("Expected video resolution")
            return
        }
        XCTAssertEqual(resolvedVideo, video)
    }

    func test_addPlaylistSelection_submitsCheckedEntriesWithSelectionOptions() async {
        let engine = FakeEngine()
        let persistence = FakeQueuePersisting()
        let model = makeModel(engine: engine, persistence: persistence)
        var picker = PlaylistPickerModel(
            dump: Self.dump(),
            existing: [(url: "https://youtu.be/two", completed: false)],
            showPlaylistBanner: true
        )
        picker.checked.insert(2)

        await model.addPlaylistSelection(model: picker, overrides: RunwayOverrides(
            kind: .audio(format: .mp3),
            destFolder: URL(fileURLWithPath: "/tmp/music"),
            audioLanguage: .code("es")
        ))

        let items = engine.submittedPlaylistItems
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.request.url), ["https://youtu.be/one", "https://youtu.be/two"])
        XCTAssertEqual(items.map(\.request.kind), [.audio(format: .mp3), .audio(format: .mp3)])
        XCTAssertEqual(items.map(\.request.audioLanguage), [.code("es"), .code("es")])
        XCTAssertEqual(items.map(\.force), [false, true])
        XCTAssertEqual(items.map(\.playlistIndex), [1, 2])
        XCTAssertEqual(items.map(\.prefetched?.extractor), ["youtube", "youtube"])
        XCTAssertEqual(Set(items.map(\.playlistGroupID)).count, 1)
        XCTAssertEqual(
            persistence.playlistGroupSaves.last?.first?.sourceURL,
            AppModel.trimmedPlaylistSourceURL(picker.dump.sourceURL)
        )
    }

    func test_addPlaylistSelection_allDuplicatesSkippedDoesNotCreateOrphanGroup() async {
        let engine = FakeEngine()
        engine.stubPlaylistSubmitIDs([])
        let persistence = FakeQueuePersisting()
        let model = makeModel(engine: engine, persistence: persistence)
        var picker = PlaylistPickerModel(
            dump: Self.dump(),
            existing: [],
            showPlaylistBanner: false
        )
        picker.checked = [1]

        await model.addPlaylistSelection(model: picker, overrides: RunwayOverrides())

        XCTAssertTrue(model.playlistGroups.isEmpty)
        XCTAssertTrue(persistence.playlistGroupSaves.isEmpty)
        XCTAssertEqual(engine.submittedPlaylistItems.count, 1)
    }

    func test_addPlaylistSelection_reusesLiveGroupForMatchingSourceURL() async {
        let groupID = UUID()
        let engine = FakeEngine()
        let persistence = FakeQueuePersisting()
        persistence.stubPlaylistGroups([
            PersistedPlaylistGroup(
                id: groupID,
                title: "Existing Mix",
                sourceURL: Self.sourceURL,
                isCollapsed: true
            )
        ])
        engine.setRestoreSnapshot(QueueSnapshot(
            jobs: [AppModelTestHelpers.jobSnapshot(playlistGroupID: groupID)],
            revision: 1,
            queueHalt: nil,
            generatedAt: .init(),
            hostRateSummary: [:],
            isOnline: true
        ))
        let model = makeModel(engine: engine, persistence: persistence)
        await model.performLaunchSetup()
        let picker = PlaylistPickerModel(
            dump: Self.dump(),
            existing: [],
            showPlaylistBanner: true
        )

        await model.addPlaylistSelection(model: picker, overrides: RunwayOverrides())

        XCTAssertEqual(Set(engine.submittedPlaylistItems.map(\.playlistGroupID)), [groupID])
        XCTAssertEqual(model.playlistGroups.map(\.id), [groupID])
    }

    func test_addPlaylistSelection_reusesLiveGroupWhenSourceURLDiffersOnlyByWhitespace() async {
        let groupID = UUID()
        let engine = FakeEngine()
        let persistence = FakeQueuePersisting()
        persistence.stubPlaylistGroups([
            PersistedPlaylistGroup(
                id: groupID,
                title: "Existing Mix",
                sourceURL: "  \(Self.sourceURL)  ",
                isCollapsed: true
            )
        ])
        engine.setRestoreSnapshot(QueueSnapshot(
            jobs: [AppModelTestHelpers.jobSnapshot(playlistGroupID: groupID)],
            revision: 1,
            queueHalt: nil,
            generatedAt: .init(),
            hostRateSummary: [:],
            isOnline: true
        ))
        let model = makeModel(engine: engine, persistence: persistence)
        await model.performLaunchSetup()
        let picker = PlaylistPickerModel(
            dump: Self.dump(),
            existing: [],
            showPlaylistBanner: true
        )

        await model.addPlaylistSelection(model: picker, overrides: RunwayOverrides())

        XCTAssertEqual(Set(engine.submittedPlaylistItems.map(\.playlistGroupID)), [groupID])
        XCTAssertEqual(model.playlistGroups.map(\.id), [groupID])
        XCTAssertEqual(persistence.playlistGroupSaves.count, 0)
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

    private static let sourceURL = "https://www.youtube.com/playlist?list=PL1234567890"

    private static func dump() -> PlaylistDump {
        PlaylistDump(
            title: "Road Trip Mix",
            uploader: "Sampler",
            extractor: "youtube:tab",
            sourceURL: sourceURL,
            entries: [
                PlaylistEntry(
                    watchURL: "https://youtu.be/one",
                    title: "One",
                    durationSeconds: 11,
                    thumbnailURL: nil,
                    extractor: "youtube",
                    playlistIndex: 1
                ),
                PlaylistEntry(
                    watchURL: "https://youtu.be/two",
                    title: "Two",
                    durationSeconds: 22,
                    thumbnailURL: nil,
                    extractor: "youtube",
                    playlistIndex: 2
                )
            ]
        )
    }
}
