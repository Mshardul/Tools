@testable import MediaGrabber
import XCTest

final class FirstRunChromeTests: XCTestCase {
    func test_firstRun_isNumberedStrip() {
        XCTAssertEqual(FirstRunStep.presentation, .numberedStrip)
        XCTAssertEqual(FirstRunStep.strip.map(\.index), [1, 2, 3])
        XCTAssertEqual(
            FirstRunStep.strip.map(\.title),
            ["Paste a link", "Pick a format", "Press Grab"]
        )
    }
}
