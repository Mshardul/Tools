@testable import GrabberKit
import XCTest

final class ExtractorContextTests: XCTestCase {
    func testNoneHasNilFlags() {
        XCTAssertEqual(ExtractorContext.none.pluginDirs, [])
        XCTAssertNil(ExtractorContext.none.potBaseURL)
        XCTAssertNil(ExtractorContext.none.playerClient)
        XCTAssertNil(ExtractorContext.none.cookieArgument)
    }
}
