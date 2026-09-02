@testable import GrabberKit
import TestSupport
import XCTest

final class CookieResolverSafariTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/tester")

    private var cookiePath: String {
        home.appendingPathComponent(
            "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
        ).path
    }

    private func resolver(exists: Bool, readable: Bool) -> CookieResolver {
        var fm = FakeFileManaging()
        if exists {
            fm.files = [cookiePath]
        }
        if readable {
            fm.readable = [cookiePath]
        }
        return CookieResolver(fileManager: fm, home: home)
    }

    func test_noContainer() {
        XCTAssertEqual(resolver(exists: false, readable: false).safariAccess(), .noContainer)
    }

    func test_granted() {
        XCTAssertEqual(resolver(exists: true, readable: true).safariAccess(), .granted)
    }

    func test_denied() {
        XCTAssertEqual(resolver(exists: true, readable: false).safariAccess(), .denied)
    }
}
