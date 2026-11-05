@testable import GrabberKit
import TestSupport
import XCTest

final class EnvironmentProbeTests: XCTestCase {
    private let resources = URL(fileURLWithPath: "/bundle/Resources")
    private let support = URL(fileURLWithPath: "/support")

    private func probe(runner: FakeProcessRunner, present: Set<String>) -> EnvironmentProbe {
        EnvironmentProbe(
            runner: runner,
            tools: ManagedTools(resourceRoot: resources, supportRoot: support, isExecutable: { _ in true }),
            isExecutable: { present.contains($0.path) }
        )
    }

    func test_bundledTools_parseVersions() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout("2025.09.26\n"), forPathEndingIn: "yt-dlp")
        runner.script(.stdout("ffmpeg version 8.0 Copyright\n"), forPathEndingIn: "ffmpeg")
        runner.script(.stdout("ffprobe version 8.0 Copyright\n"), forPathEndingIn: "ffprobe")
        let tools = ManagedTools(resourceRoot: resources, supportRoot: support, isExecutable: { _ in true })
        let present = [tools.bundledYtDlp.path, tools.ffmpegURL.path, tools.ffprobeURL.path]
        let report = await probe(runner: runner, present: Set(present)).probe()
        XCTAssertNil(report.brew)
        XCTAssertEqual(report.ytDlp?.version, "2025.09.26")
        XCTAssertEqual(report.ffmpeg?.version, "8.0")
        XCTAssertEqual(report.ffprobe?.version, "8.0")
        XCTAssertTrue(report.isReadyForDownloads)
    }

    func test_updatedCopyWinsWhenNewer() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout("2025.01.01\n"), forExactPath: resources.appendingPathComponent("Tools/yt-dlp").path)
        runner.script(.stdout("2026.02.02\n"), forExactPath: support.appendingPathComponent("bin/yt-dlp").path)
        let tools = ManagedTools(resourceRoot: resources, supportRoot: support, isExecutable: { _ in true })
        let report = await probe(
            runner: runner,
            present: [tools.bundledYtDlp.path, tools.updatedYtDlp.path]
        ).probe()
        XCTAssertEqual(report.ytDlp?.path, tools.updatedYtDlp)
        XCTAssertEqual(report.ytDlp?.version, "2026.02.02")
    }

    func test_olderUpdate_keepsTheBundledCopy() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout("2026.02.02\n"), forExactPath: resources.appendingPathComponent("Tools/yt-dlp").path)
        runner.script(.stdout("2025.01.01\n"), forExactPath: support.appendingPathComponent("bin/yt-dlp").path)
        let tools = ManagedTools(resourceRoot: resources, supportRoot: support, isExecutable: { _ in true })
        let report = await probe(
            runner: runner,
            present: [tools.bundledYtDlp.path, tools.updatedYtDlp.path]
        ).probe()
        XCTAssertEqual(report.ytDlp?.path, tools.bundledYtDlp)
    }

    func test_corruptUpdate_keepsTheBundledCopy() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout("2025.09.26\n"), forExactPath: resources.appendingPathComponent("Tools/yt-dlp").path)
        runner.script(.stderr("bad", exitCode: 1), forExactPath: support.appendingPathComponent("bin/yt-dlp").path)
        let tools = ManagedTools(resourceRoot: resources, supportRoot: support, isExecutable: { _ in true })
        let report = await probe(
            runner: runner,
            present: [tools.bundledYtDlp.path, tools.updatedYtDlp.path]
        ).probe()
        XCTAssertEqual(report.ytDlp?.path, tools.bundledYtDlp)
    }

    func test_missingDownloader_isNotReady() async {
        let report = await probe(runner: FakeProcessRunner(), present: []).probe()
        XCTAssertNil(report.ytDlp)
        XCTAssertNil(report.ffmpeg)
        XCTAssertFalse(report.isReadyForDownloads)
    }

    func test_environmentReport_driftVerdict_nilWhenYtDlpMissing() {
        let report = EnvironmentReport(brew: nil, ytDlp: nil, ffmpeg: nil)
        XCTAssertNil(report.ytDlpDriftVerdict)
    }

    func test_environmentReport_driftVerdict_currentWhenAtOrAboveMinimum() {
        let ytDlp = ToolInfo(path: URL(fileURLWithPath: "/bundle/Tools/yt-dlp"), version: "2099.01.01")
        let report = EnvironmentReport(brew: nil, ytDlp: ytDlp, ffmpeg: nil)
        XCTAssertEqual(report.ytDlpDriftVerdict, .current)
    }

    func test_environmentReport_driftVerdict_driftWhenBelowMinimum() {
        let ytDlp = ToolInfo(path: URL(fileURLWithPath: "/bundle/Tools/yt-dlp"), version: "2000.01.01")
        let report = EnvironmentReport(brew: nil, ytDlp: ytDlp, ffmpeg: nil)
        guard case .drift = report.ytDlpDriftVerdict else {
            XCTFail("expected drift verdict, got \(String(describing: report.ytDlpDriftVerdict))")
            return
        }
    }
}
