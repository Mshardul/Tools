@testable import GrabberKit
import TestSupport
import XCTest

// Real yt-dlp against a Creative-Commons source; gated on MG_LIVE_TESTS=1 (see README).
final class DownloadEngineLiveTests: XCTestCase {
    private let ytDlp = URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp")

    func test_live_realDownloadReachesCompleted() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MG_LIVE_TESTS"] == "1",
            "set MG_LIVE_TESTS=1 to run"
        )
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let engine = DownloadEngine(
            dependencies: .live(ytDlpURL: ytDlp),
            preferences: Preferences(defaults: defaults)
        )
        let collector = EventCollector(engine.events)
        let request = DownloadRequest(
            url: "https://archive.org/details/BigBuckBunny_124",
            destFolder: dir,
            kind: .video(maxHeight: 360),
            container: "mp4"
        )

        let result = await engine.submit(request, force: false, prefetchedMetadata: nil)
        guard case let .queued(id) = result else {
            return XCTFail("expected .queued")
        }
        let reached = await collector.waitForState(id, { $0 == .completed }, timeout: 300)
        XCTAssertTrue(reached)

        let job = try XCTUnwrap(collector.latestSnapshot()?.jobs.first { $0.id == id })
        XCTAssertEqual(job.title, "Big Buck Bunny")
        XCTAssertEqual(job.progress?.fraction, 1.0)
        XCTAssertFalse(job.outputFiles.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: job.outputFiles[0].path))
    }
}
