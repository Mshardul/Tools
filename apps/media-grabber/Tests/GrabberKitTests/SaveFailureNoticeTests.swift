@testable import GrabberKit
import XCTest

final class SaveFailureNoticeTests: XCTestCase {
    func testDiskFullNamesTheDownloadList() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        XCTAssertEqual(
            SaveFailureNotice.sentence(file: "queue.json", error: error),
            "The download list couldn't be saved because the disk is full. Free some space, then try again."
        )
    }

    func testNotPermittedNamesHistory() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        XCTAssertEqual(
            SaveFailureNotice.sentence(file: "history.json", error: error),
            "Download history couldn't be saved because the save folder isn't writable. "
                + "Make the folder writable, then try again."
        )
    }

    func testUnavailableNamesTheColumnLayout() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        XCTAssertEqual(
            SaveFailureNotice.sentence(file: "columns.json", error: error),
            "The column layout couldn't be saved. Check that the save folder is available, then try again."
        )
    }
}
