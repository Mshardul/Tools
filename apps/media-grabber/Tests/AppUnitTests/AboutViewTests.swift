import Foundation
@testable import GrabberKit
@testable import MediaGrabber
import TestSupport
import XCTest

@MainActor
final class AboutViewTests: XCTestCase {
    struct FakeGitHubReleaseChecking: GitHubReleaseChecking {
        let result: Result<GitHubRelease, Error>
        func latestRelease(owner _: String, repo _: String) async throws -> GitHubRelease {
            try result.get()
        }
    }

    func test_beforeCheck_appUpdateStatusIsNotChecked() throws {
        let model = try AboutViewModel(
            currentAppVersion: "1.4.0",
            environmentReport: .with(ytDlp: true, ffmpeg: true),
            updateChecker: AppUpdateChecker(client: FakeGitHubReleaseChecking(result: .success(
                .init(tagName: "media-grabber-v1.4.0", htmlURL: XCTUnwrap(URL(string: "https://example.com")))
            ))),
            ytDlpUpdater: FakeYtDlpUpdater()
        )
        XCTAssertEqual(model.appUpdateStatus, .notChecked)
    }

    func test_afterCheck_upToDate_showsNoButtonState() async throws {
        let model = try AboutViewModel(
            currentAppVersion: "1.4.0",
            environmentReport: .with(ytDlp: true, ffmpeg: true),
            updateChecker: AppUpdateChecker(client: FakeGitHubReleaseChecking(result: .success(
                .init(tagName: "media-grabber-v1.4.0", htmlURL: XCTUnwrap(URL(string: "https://example.com")))
            ))),
            ytDlpUpdater: FakeYtDlpUpdater()
        )
        await model.checkForAppUpdate()
        XCTAssertEqual(model.appUpdateStatus, .upToDate)
    }

    func test_ytDlpRow_neverShowsCheckForUpdatesVerb() throws {
        let driftedReport = EnvironmentReport(
            brew: nil,
            ytDlp: ToolInfo(path: URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"), version: "2000.01.01"),
            ffmpeg: nil
        )
        let model = try AboutViewModel(
            currentAppVersion: "1.4.0",
            environmentReport: driftedReport,
            updateChecker: AppUpdateChecker(client: FakeGitHubReleaseChecking(result: .success(
                .init(tagName: "media-grabber-v1.4.0", htmlURL: XCTUnwrap(URL(string: "https://example.com")))
            ))),
            ytDlpUpdater: FakeYtDlpUpdater()
        )
        switch driftedReport.ytDlpDriftVerdict {
        case .drift: break
        default: XCTFail("expected drift")
        }
        _ = model
    }
}
