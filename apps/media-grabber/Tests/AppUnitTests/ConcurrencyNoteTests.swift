@testable import MediaGrabber
import XCTest

final class ConcurrencyNoteTests: XCTestCase {
    func test_trueOnlyWhenNewBelowRunning() {
        XCTAssertTrue(shouldShowConcurrencyNote(newValue: 2, runningCount: 3))
        XCTAssertFalse(shouldShowConcurrencyNote(newValue: 3, runningCount: 3))
        XCTAssertFalse(shouldShowConcurrencyNote(newValue: 4, runningCount: 3))
        XCTAssertFalse(shouldShowConcurrencyNote(newValue: 3, runningCount: 0))
    }
}
