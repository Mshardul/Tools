@testable import GrabberKit
import TestSupport
import XCTest

final class YtDlpUpdaterTests: XCTestCase {
    func testReinstallSucceedsReportsNewVersion() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout("", exitCode: 0), forPathEndingIn: "brew")
        let probe = FakeEnvironmentProbe(EnvironmentReport(
            brew: nil,
            ytDlp: ToolInfo(path: URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"), version: "2026.08.01"),
            ffmpeg: nil
        ))
        let updater = YtDlpUpdater(runner: runner, probe: probe)
        let result = await updater.reinstallToMinimum()
        XCTAssertEqual(result, .success(newVersion: "2026.08.01"))
    }

    func testReinstallFailsReportsFailureReason() async {
        let runner = FakeProcessRunner()
        runner.script(.stderr("Error: could not reinstall yt-dlp", exitCode: 1), forPathEndingIn: "brew")
        let probe = FakeEnvironmentProbe(EnvironmentReport(brew: nil, ytDlp: nil, ffmpeg: nil))
        let updater = YtDlpUpdater(runner: runner, probe: probe)
        let result = await updater.reinstallToMinimum()
        guard case .failure = result else {
            XCTFail("expected failure, got \(result)")
            return
        }
    }

    func testReinstallInvokesBrewReinstallYtDlp() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout("", exitCode: 0), forPathEndingIn: "brew")
        let probe = FakeEnvironmentProbe(EnvironmentReport(
            brew: nil,
            ytDlp: ToolInfo(path: URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"), version: "2026.08.01"),
            ffmpeg: nil
        ))
        let updater = YtDlpUpdater(runner: runner, probe: probe)
        _ = await updater.reinstallToMinimum()
        XCTAssertEqual(runner.launches.last?.executableURL.lastPathComponent, "brew")
        XCTAssertEqual(runner.launches.last?.arguments, ["reinstall", "yt-dlp"])
    }
}
