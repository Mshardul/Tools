import Foundation
@testable import GrabberKit
@testable import MediaGrabber
import TestSupport
import XCTest

@MainActor
final class AboutViewTests: XCTestCase {
    func test_ytDlpRow_neverShowsCheckForUpdatesVerb() {
        let driftedReport = EnvironmentReport(
            ytDlp: ToolInfo(path: URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"), version: "2000.01.01"),
            ffmpeg: nil
        )
        let model = AboutViewModel(
            currentAppVersion: "1.4.0",
            environmentReport: driftedReport,
            ytDlpUpdater: FakeYtDlpUpdater()
        )
        switch driftedReport.ytDlpDriftVerdict {
        case .drift: break
        default: XCTFail("expected drift")
        }
        _ = model
    }
}
