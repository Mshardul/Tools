@testable import GrabberKit
@testable import MediaGrabber
import XCTest

final class PlaylistPickerModelTests: XCTestCase {
    func test_init_checksAllEntriesExceptWarnedRows() {
        let model = PlaylistPickerModel(
            dump: dump(),
            existing: [
                (url: "https://example.com/tide", completed: false),
                (url: "https://example.com/drift", completed: true)
            ],
            showPlaylistBanner: true
        )

        XCTAssertEqual(model.checked, [1])
        XCTAssertEqual(model.warnings[2], .inQueue)
        XCTAssertEqual(model.warnings[3], .alreadySaved)
        XCTAssertTrue(model.showPlaylistBanner)
        XCTAssertEqual(model.filter, "")
    }

    func test_init_handlesDuplicateExistingURLsAndPrefersCompletedWarning() {
        let model = PlaylistPickerModel(
            dump: dump(),
            existing: [
                (url: "https://example.com/tide", completed: false),
                (url: "https://example.com/tide", completed: true)
            ],
            showPlaylistBanner: false
        )

        XCTAssertEqual(model.warnings[2], .alreadySaved)
        XCTAssertFalse(model.checked.contains(2))
    }

    func test_selectAllFiltered_checksOnlyMatchingTitleRows() {
        var model = PlaylistPickerModel(
            dump: dump(),
            existing: [(url: "https://example.com/tide", completed: false)],
            showPlaylistBanner: false
        )
        model.checked = []
        model.filter = "Tide"

        model.selectAllFiltered()

        XCTAssertEqual(model.checked, [2])
    }

    func test_selectNoneFiltered_unchecksOnlyMatchingTitleRows() {
        var model = PlaylistPickerModel(
            dump: dump(),
            existing: [],
            showPlaylistBanner: false
        )
        model.filter = "tide"

        model.selectNoneFiltered()

        XCTAssertEqual(model.checked, [1, 3])
    }

    func test_footerLine_omitsOverlapWhenNoCheckedWarningAndSkipsUnknownDuration() {
        var model = PlaylistPickerModel(
            dump: dump(),
            existing: [(url: "https://example.com/tide", completed: false)],
            showPlaylistBanner: false
        )
        model.checked = [1, 3]

        XCTAssertEqual(model.durationSum, 3661)
        XCTAssertEqual(model.footerLine, "2 of 3 selected · ≈ 1:01:01")
    }

    func test_footerLine_countsCheckedWarnings() {
        var model = PlaylistPickerModel(
            dump: dump(),
            existing: [
                (url: "https://example.com/tide", completed: false),
                (url: "https://example.com/drift", completed: true)
            ],
            showPlaylistBanner: false
        )
        model.checked = [1, 2, 3]

        XCTAssertEqual(model.overlapCount, 2)
        XCTAssertEqual(model.footerLine, "3 of 3 selected · 2 already in queue · ≈ 1:01:01")
    }

    private func dump() -> PlaylistDump {
        PlaylistDump(
            title: "Playlist",
            uploader: "Uploader",
            extractor: "Example",
            sourceURL: "https://example.com/playlist",
            entries: [
                entry(index: 1, title: "Still Water", durationSeconds: 3600),
                entry(index: 2, title: "Moon Tide", durationSeconds: nil),
                entry(index: 3, title: "Night Drift", durationSeconds: 61)
            ]
        )
    }

    private func entry(
        index: Int,
        title: String,
        durationSeconds: Int?
    ) -> PlaylistEntry {
        PlaylistEntry(
            watchURL: "https://example.com/\(title.split(separator: " ").last!.lowercased())",
            title: title,
            durationSeconds: durationSeconds,
            thumbnailURL: nil,
            extractor: "Example",
            playlistIndex: index
        )
    }
}
