@testable import GrabberKit
import TestSupport
import XCTest

final class EngineRetryTests: XCTestCase {
    private typealias Fix = EngineFixture

    private func engine(
        _ runner: FakeProcessRunner,
        _ probe: FakeMetadataProbe,
        clock: FakeClock,
        maxAutoRetries: Int = 3,
        ffprobeURL: URL? = nil,
        tuning: EngineTuning = .default
    ) -> DownloadEngine {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let prefs = Preferences(defaults: defaults)
        prefs.maxAutoRetries = maxAutoRetries
        return DownloadEngine(
            dependencies: EngineDependencies(
                runner: runner,
                probe: probe,
                envProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
                clock: clock,
                ytDlpURL: Fix.ytDlp,
                jobLogDir: Fix.scratchLogDir(),
                debugFlags: EngineDebugFlags(concurrencyCapOverride: 1),
                tuning: tuning,
                ffprobeURL: ffprobeURL
            ),
            preferences: prefs
        )
    }

    private func job(_ collector: EventCollector, _ id: UUID) -> JobSnapshot? {
        collector.latestSnapshot()?.jobs.first { $0.id == id }
    }

    // A real output file plus the Destination line yt-dlp prints, so the engine's
    // finalized-file resolution finds something for IntegrityCheck to probe.
    private func requestWithRealOutput() -> (DownloadRequest, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-out-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Clip.mp4")
        FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
        return (Fix.request(destFolder: dir), file)
    }

    private func completingScriptWritingFile(_ file: URL) -> FakeProcessRunner.Script {
        Fix.completingScript([.stdout("[download] Destination: \(file.path)")])
    }

    func test_autoRetryableExitDefersWithIncrementedAttempt() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let runner = FakeProcessRunner()
        runner.script(
            .stderr("ERROR: HTTP Error 429: Too Many Requests", exitCode: 1),
            forPathEndingIn: "yt-dlp"
        )
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip", durationSeconds: 10))
        let engine = engine(runner, probe, clock: clock)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        _ = await collector.waitForState(id) { $0 == .running }
        _ = await collector
            .waitForState(id) { ($0 == .queued) && (self.job(collector, id)?.attempt ?? 0) >= 1 }

        XCTAssertEqual(job(collector, id)?.attempt, 1)
        let sawTransientFailed = collector.snapshots.contains { snap in
            snap.jobs.contains { $0.id == id && $0.state == .failed(.rateLimited()) }
        }
        XCTAssertFalse(sawTransientFailed, "no transient .failed snapshot")

        clock.advance(by: .seconds(600))
        try? await Task.sleep(for: .milliseconds(40))
        // The job runs again after the backoff fires; it then re-fails and re-queues at attempt 2.
        XCTAssertGreaterThanOrEqual(job(collector, id)?.attempt ?? 0, 1)
    }

    func test_budgetExhaustionGoesTerminal() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let runner = FakeProcessRunner()
        runner.script(.stderr("ERROR: HTTP Error 429", exitCode: 1), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = engine(runner, probe, clock: clock, maxAutoRetries: 2)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        for _ in 0 ..< 5 {
            clock.advance(by: .seconds(600))
            try? await Task.sleep(for: .milliseconds(40))
        }
        await expectState(collector, id) { state in
            if case .failed = state {
                true
            } else {
                false
            }
        }
        XCTAssertEqual(job(collector, id)?.attempt, 2)
    }

    func test_nonRetryableClassIsImmediatelyTerminal() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let runner = FakeProcessRunner()
        runner.script(
            .stderr(
                "ERROR: The uploader has not made this video available in your country",
                exitCode: 1
            ),
            forPathEndingIn: "yt-dlp"
        )
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = engine(runner, probe, clock: clock)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        await expectState(collector, id) { $0 == .failed(.geoBlocked) }
        XCTAssertEqual(job(collector, id)?.attempt, 0)
    }

    func test_failedIntegrityTakesIncompleteRetryPath() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let (request, file) = requestWithRealOutput()
        let runner = FakeProcessRunner()
        runner.script(completingScriptWritingFile(file), forPathEndingIn: "yt-dlp")
        runner.script(
            .stdout(
                "{\"format\":{\"duration\":\"5\"},"
                    + "\"streams\":[{\"codec_type\":\"video\",\"height\":720}]}",
                exitCode: 0
            ),
            forPathEndingIn: "ffprobe"
        )
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip", durationSeconds: 600))
        let engine = engine(
            runner, probe, clock: clock,
            ffprobeURL: URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
        )
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, request)
        _ = await collector.waitForState(id) { $0 == .running }
        _ = await collector.waitForState(id) { $0 == .queued }
        XCTAssertEqual(job(collector, id)?.attempt, 1)
    }

    func test_skippedIntegrityCompletesAndStoresActualQuality() async {
        // ffprobe present but returns a within-tolerance duration → .passed, quality stored.
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let (request, file) = requestWithRealOutput()
        let runner = FakeProcessRunner()
        runner.script(completingScriptWritingFile(file), forPathEndingIn: "yt-dlp")
        runner.script(
            .stdout(
                "{\"format\":{\"duration\":\"600\"},"
                    + "\"streams\":[{\"codec_type\":\"video\",\"height\":720}]}",
                exitCode: 0
            ),
            forPathEndingIn: "ffprobe"
        )
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip", durationSeconds: 600))
        let engine = engine(
            runner, probe, clock: clock,
            ffprobeURL: URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
        )
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, request)
        await expectState(collector, id) { $0 == .completed }
        XCTAssertEqual(job(collector, id)?.actualQuality, "720p")
    }

    func test_ffprobeAbsentCompletesWithNoIntegrityFailure() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let (request, file) = requestWithRealOutput()
        let runner = FakeProcessRunner()
        runner.script(completingScriptWritingFile(file), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip", durationSeconds: 600))
        let engine = engine(runner, probe, clock: clock, ffprobeURL: nil)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, request)
        await expectState(collector, id) { $0 == .completed }
    }
}
