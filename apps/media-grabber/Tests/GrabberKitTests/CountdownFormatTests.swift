@testable import GrabberKit
import XCTest

final class CountdownFormatTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 0)

    private func format(_ secs: TimeInterval) -> String {
        CountdownFormat.mmss(until: t0.addingTimeInterval(secs), now: t0)
    }

    func testBoundaries() {
        XCTAssertEqual(format(0), "0:00")
        XCTAssertEqual(format(-5), "0:00")
        XCTAssertEqual(format(59), "0:59")
        XCTAssertEqual(format(60), "1:00")
        XCTAssertEqual(format(134), "2:14")
        XCTAssertEqual(format(599), "9:59")
    }
}
