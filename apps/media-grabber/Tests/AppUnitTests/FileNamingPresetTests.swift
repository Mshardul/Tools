@testable import MediaGrabber
import XCTest

final class FileNamingPresetTests: XCTestCase {
    func test_templates() {
        XCTAssertEqual(FileNamingPreset.title.template, "%(title)s.%(ext)s")
        XCTAssertEqual(
            FileNamingPreset.titleAndChannel.template,
            "%(title)s - %(uploader)s.%(ext)s"
        )
        XCTAssertEqual(
            FileNamingPreset.dateAndTitle.template,
            "%(upload_date>%Y-%m-%d)s - %(title)s.%(ext)s"
        )
        XCTAssertNil(FileNamingPreset.custom.template)
    }

    func test_matching() {
        XCTAssertEqual(FileNamingPreset.matching("%(title)s.%(ext)s"), .title)
        XCTAssertEqual(FileNamingPreset.matching("%(id)s.%(ext)s"), .custom)
    }
}
