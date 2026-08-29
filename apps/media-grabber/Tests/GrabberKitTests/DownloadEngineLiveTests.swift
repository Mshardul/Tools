@testable import GrabberKit
import XCTest

// Real yt-dlp against a Creative-Commons source; gated on MG_LIVE_TESTS=1 (see README).
@MainActor
final class DownloadEngineLiveTests: XCTestCase {
    private let ytDlp = URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp")

    private func waitUntilTerminal(_ job: DownloadJob, timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch job.state {
            case .completed, .cancelled, .failed:
                return
            default:
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    func test_live_realDownloadReachesCompleted() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MG_LIVE_TESTS"] == "1",
            "set MG_LIVE_TESTS=1 to run"
        )
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let engine = DownloadEngine(ytDlpURL: ytDlp)
        let request = DownloadRequest(
            url: "https://archive.org/details/BigBuckBunny_124",
            destFolder: dir,
            kind: .video(maxHeight: 360),
            container: "mp4"
        )

        let job = await engine.submit(request)
        await waitUntilTerminal(job, timeout: 300)

        guard case .completed = job.state else {
            return XCTFail("expected .completed, got \(job.state)")
        }
        XCTAssertEqual(job.title, "Big Buck Bunny")
        XCTAssertEqual(job.progress?.fraction, 1.0)
        XCTAssertFalse(job.outputFiles.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: job.outputFiles[0].path))
    }
}
