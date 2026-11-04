@testable import MediaGrabber
import XCTest

final class PreferenceFieldCommitTests: XCTestCase {
    func testBlankCustomFilenameRevertsToTheSavedTemplate() {
        XCTAssertEqual(
            PreferenceFieldCommit.filename(draft: "   ", saved: "%(title)s.%(ext)s"),
            "%(title)s.%(ext)s"
        )
    }

    func testCustomFilenameKeepsATrimmedValue() {
        XCTAssertEqual(
            PreferenceFieldCommit.filename(draft: "  %(id)s.%(ext)s  ", saved: "%(title)s.%(ext)s"),
            "%(id)s.%(ext)s"
        )
    }

    func testBlankProxyClearsAndATypedProxyIsTrimmed() {
        XCTAssertNil(PreferenceFieldCommit.proxy(draft: "  "))
        XCTAssertEqual(
            PreferenceFieldCommit.proxy(draft: "  http://127.0.0.1:8080  "),
            "http://127.0.0.1:8080"
        )
    }
}
