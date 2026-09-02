@testable import GrabberKit
import XCTest

final class CookieSourceTests: XCTestCase {
    func test_browserKey_perCase() {
        XCTAssertEqual(CookieSource.none.browserKey, "none")
        XCTAssertEqual(CookieSource.safari.browserKey, "safari")
        XCTAssertEqual(CookieSource.chrome.browserKey, "chrome")
        XCTAssertEqual(CookieSource.brave.browserKey, "brave")
        XCTAssertEqual(CookieSource.edge.browserKey, "edge")
        XCTAssertEqual(CookieSource.firefox(profile: "dev").browserKey, "firefox")
        XCTAssertEqual(CookieSource.firefox(profile: nil).browserKey, "firefox")
    }

    func test_ytDlpSpec_perCase() {
        XCTAssertNil(CookieSource.none.ytDlpSpec)
        XCTAssertEqual(CookieSource.safari.ytDlpSpec, "safari")
        XCTAssertEqual(CookieSource.chrome.ytDlpSpec, "chrome")
        XCTAssertEqual(CookieSource.brave.ytDlpSpec, "brave")
        XCTAssertEqual(CookieSource.edge.ytDlpSpec, "edge")
        XCTAssertEqual(
            CookieSource.firefox(profile: "default-release").ytDlpSpec,
            "firefox:default-release"
        )
        XCTAssertEqual(CookieSource.firefox(profile: nil).ytDlpSpec, "firefox")
    }

    func test_isNone() {
        XCTAssertTrue(CookieSource.none.isNone)
        XCTAssertFalse(CookieSource.safari.isNone)
    }

    func test_codableRoundTrip_includingFirefoxProfile() throws {
        let cases: [CookieSource] = [.none, .safari, .chrome, .brave, .edge,
                                     .firefox(profile: "x"), .firefox(profile: nil)]
        for source in cases {
            let data = try JSONEncoder().encode(source)
            let decoded = try JSONDecoder().decode(CookieSource.self, from: data)
            XCTAssertEqual(decoded, source)
        }
    }
}
