@testable import MediaGrabber
import XCTest

final class AppIconTests: XCTestCase {
    func test_appIcon_isBundled() {
        let icon = Bundle(for: AppDelegate.self).url(forResource: "AppIcon", withExtension: "icns")
        XCTAssertNotNil(icon)
    }
}
