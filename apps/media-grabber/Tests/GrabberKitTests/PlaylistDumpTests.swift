@testable import GrabberKit
import TestSupport
import XCTest

final class PlaylistDumpTests: XCTestCase {
    func testDecodesEntriesAndBuildsWatchURLFromId() throws {
        let json = Fixture.text("ytdlp-J-flat-playlist.json")
        let dump = try PlaylistDump.decode(json, pasteURL: "https://example.com/x").get()
        XCTAssertEqual(dump.title, "Focus — deep work")
        XCTAssertEqual(dump.uploader, "Ambient Dept")
        XCTAssertEqual(dump.sourceURL, "https://www.youtube.com/playlist?list=PLbpi6ZahtOH6")
        XCTAssertEqual(dump.entries.count, 2)
        XCTAssertEqual(dump.entries[0].watchURL, "https://www.youtube.com/watch?v=aaaaaaaaaaa")
        XCTAssertEqual(dump.entries[0].durationSeconds, 252)
        XCTAssertEqual(dump.entries[0].extractor, "Youtube")
        XCTAssertEqual(dump.entries[0].playlistIndex, 1)
        XCTAssertEqual(dump.entries[1].watchURL, "https://www.youtube.com/watch?v=bbbbbbbbbbb")
        XCTAssertEqual(dump.entries[1].durationSeconds, 390)
    }

    func testEmptyEntriesIsMalformed() {
        let json = #"{"title":"Empty","_type":"playlist","entries":[]}"#
        XCTAssertEqual(
            PlaylistDump.decode(json, pasteURL: "https://x"),
            .failure(.malformedOutput)
        )
    }
}
