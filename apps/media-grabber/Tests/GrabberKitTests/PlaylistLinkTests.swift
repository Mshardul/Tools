@testable import GrabberKit
import XCTest

final class PlaylistLinkTests: XCTestCase {
    func testWatchWithListIsSingleVideo() {
        XCTAssertEqual(
            PlaylistLink.classify("https://www.youtube.com/watch?v=abc123abc12&list=PLdeadbeef"),
            .singleVideo
        )
    }

    func testShortsAndYoutuBeAreSingleVideo() {
        XCTAssertEqual(PlaylistLink.classify("https://youtu.be/abc123abc12"), .singleVideo)
        XCTAssertEqual(
            PlaylistLink.classify("https://www.youtube.com/shorts/abc123abc12"),
            .singleVideo
        )
    }

    func testPLPlaylistPage() {
        XCTAssertEqual(
            PlaylistLink.classify("https://www.youtube.com/playlist?list=PLbpi6ZahtOH6"),
            .youtubePlaylist
        )
        XCTAssertEqual(
            PlaylistLink.classify("https://music.youtube.com/playlist?list=PLbpi6ZahtOH6"),
            .youtubePlaylist
        )
    }

    func testMixWatchLaterLikedUploadsChannelUnsupported() {
        let samples = [
            "https://www.youtube.com/playlist?list=RDxxxxxxxx",
            "https://www.youtube.com/playlist?list=WL",
            "https://www.youtube.com/playlist?list=LL",
            "https://www.youtube.com/playlist?list=UUxxxxxxxx",
            "https://www.youtube.com/playlist?list=OLxxxxxxxx",
            "https://www.youtube.com/@foo/videos",
            "https://www.youtube.com/channel/UCxxx/videos",
            "https://www.youtube.com/c/foo/videos",
            "https://www.youtube.com/user/foo/videos"
        ]
        for url in samples {
            XCTAssertEqual(PlaylistLink.classify(url), .youtubeUnsupported, url)
        }
    }

    func testNonYouTubeIsSingleVideo() {
        XCTAssertEqual(
            PlaylistLink.classify("https://archive.org/details/foo"),
            .singleVideo
        )
    }
}
