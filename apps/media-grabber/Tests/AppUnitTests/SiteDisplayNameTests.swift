@testable import MediaGrabber
import XCTest

final class SiteDisplayNameTests: XCTestCase {
    func test_displaysYouTubeVariants() {
        XCTAssertEqual(SiteNames.display("youtube"), "YouTube")
        XCTAssertEqual(SiteNames.display("youtube:tab"), "YouTube")
        XCTAssertEqual(SiteNames.display("youtu.be"), "YouTube")
        XCTAssertEqual(SiteNames.display("m.youtube.com"), "YouTube")
    }

    func test_displaysVimeo() {
        XCTAssertEqual(SiteNames.display("vimeo"), "Vimeo")
        XCTAssertEqual(SiteNames.display("vimeo.com"), "Vimeo")
    }

    func test_displaysSoundCloud() {
        XCTAssertEqual(SiteNames.display("soundcloud"), "SoundCloud")
    }

    func test_displaysArchiveOrgAsInternetArchive() {
        XCTAssertEqual(SiteNames.display("archive.org"), "Internet Archive")
    }

    func test_unknownKeyFallsBackToRawValue() {
        XCTAssertEqual(SiteNames.display("some-new-site"), "some-new-site")
    }

    func test_genericFallsBackToWeb() {
        XCTAssertEqual(SiteNames.display("generic"), "Web")
    }
}
