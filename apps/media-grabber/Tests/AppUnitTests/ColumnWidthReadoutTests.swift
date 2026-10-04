@testable import MediaGrabber
import XCTest

final class ColumnWidthReadoutTests: XCTestCase {
    func test_format_roundsToNearestIntegerPoint() {
        XCTAssertEqual(ColumnWidthReadout.format(120.4), "120 pt")
        XCTAssertEqual(ColumnWidthReadout.format(120.6), "121 pt")
        XCTAssertEqual(ColumnWidthReadout.format(80.0), "80 pt")
    }
}
