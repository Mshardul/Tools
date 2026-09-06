@testable import GrabberKit
import XCTest

final class RateHostTests: XCTestCase {
    func testYouTubeSubdomainsFoldToOneBucket() {
        let hosts = [
            "https://www.youtube.com/watch?v=abc",
            "https://youtu.be/abc",
            "https://m.youtube.com/watch?v=abc",
            "https://music.youtube.com/watch?v=abc",
            "https://gaming.youtube.com/watch?v=abc",
            "https://www.youtube-nocookie.com/embed/abc"
        ]
        for host in hosts {
            XCTAssertEqual(RateHost(urlString: host).canonical, "youtube", host)
        }
    }

    func testWWWStrippedAndGenericHostKept() {
        XCTAssertEqual(
            RateHost(urlString: "https://www.vimeo.com/123").canonical, "vimeo.com"
        )
        XCTAssertEqual(
            RateHost(urlString: "https://archive.org/details/x").canonical, "archive.org"
        )
    }

    func testUnparseableStringResolvesToUnresolved() {
        XCTAssertEqual(RateHost(urlString: "not a url").canonical, RateHost.unresolved.canonical)
        XCTAssertEqual(RateHost(urlString: "").canonical, RateHost.unresolved.canonical)
    }

    func testHashableAndDescription() {
        let left = RateHost(urlString: "https://youtu.be/x")
        let right = RateHost(urlString: "https://youtube.com/watch?v=y")
        XCTAssertEqual(left, right)
        XCTAssertEqual(Set([left, right]).count, 1)
        XCTAssertEqual(left.description, "youtube")
    }
}
