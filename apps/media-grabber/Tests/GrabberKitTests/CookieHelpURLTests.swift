@testable import GrabberKit
import XCTest

final class CookieHelpURLTests: XCTestCase {
    func test_everyBrowserKey_yieldsAValidURL() {
        for key in ["safari", "chrome", "brave", "edge", "firefox"] {
            let url = CookieHelpURL.url(forBrowserKey: key)
            XCTAssertEqual(url.scheme, "https")
            XCTAssertTrue(url.absoluteString.contains("yt-dlp"))
            XCTAssertTrue(url.absoluteString.contains("#"))
        }
    }
}
