@testable import GrabberKit
import XCTest

final class MissingPotProviderTests: XCTestCase {
    func testMissingReportsMissing() async {
        let provider = MissingPotProvider()
        let status = await provider.status
        XCTAssertEqual(status, .missing)
        let base = await provider.baseURL
        XCTAssertNil(base)
        let dirs = await provider.pluginDirs
        XCTAssertEqual(dirs, [])
    }
}
