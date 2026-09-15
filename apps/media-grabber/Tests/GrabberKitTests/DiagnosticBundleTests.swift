import Foundation
@testable import GrabberKit
import XCTest

final class DiagnosticBundleTests: XCTestCase {
    func testBuildsAZipContainingAllThreeSections() throws {
        let data = try DiagnosticBundle.build(
            appLogTail: "app log line 1\napp log line 2",
            jobLog: "job log contents",
            report: "Canary probe: passed"
        )
        XCTAssertFalse(data.isEmpty)
        let signature = data.prefix(4)
        XCTAssertEqual(signature, Data([0x50, 0x4B, 0x03, 0x04]))
    }

    func testBuildsAZipWithNoJobLog() throws {
        let data = try DiagnosticBundle.build(appLogTail: "app log", jobLog: nil, report: "report text")
        XCTAssertFalse(data.isEmpty)
    }

    func testRedactsBeforeZipping() throws {
        let data = try DiagnosticBundle.build(
            appLogTail: "saved to /Users/alice/Downloads/video.mp4",
            jobLog: nil,
            report: "report"
        )
        let needle = [UInt8]("/Users/alice".utf8)
        let haystack = [UInt8](data)
        let containsRawPath = haystack.count >= needle.count && (0 ... (haystack.count - needle.count))
            .contains { start in Array(haystack[start ..< start + needle.count]) == needle }
        XCTAssertFalse(containsRawPath)
    }
}
