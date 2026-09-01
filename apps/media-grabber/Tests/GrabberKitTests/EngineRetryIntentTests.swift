@testable import GrabberKit
import TestSupport
import XCTest

final class EngineRetryIntentTests: XCTestCase {
    private typealias Fix = EngineFixture

    private func engine(
        _ runner: FakeProcessRunner,
        _ probe: FakeMetadataProbe,
        clock: FakeClock,
        maxAutoRetries: Int = 1,
        ffprobeURL: URL? = nil
    ) -> DownloadEngine {
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
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
                ffprobeURL: ffprobeURL
            ),
            preferences: prefs
        )
    }

    private func job(_ collector: EventCollector, _ id: UUID) -> JobSnapshot? {
        collector.latestSnapshot()?.jobs.first { $0.id == id }
    }

    private func destWithPart(stem: String) -> (URL, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-retry-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let part = dir.appendingPathComponent("\(stem).f137.mp4.part")
        FileManager.default.createFile(atPath: part.path, contents: Data("partial".utf8))
        return (dir, part)
    }

    // Drives a job to terminal .failed, past the single-retry budget.
    private func failedJob(
        _ engine: DownloadEngine,
        _ collector: EventCollector,
        _ clock: FakeClock,
        request: DownloadRequest
    ) async -> UUID {
        let id = await submitJob(engine, request)
        for _ in 0 ..< 4 {
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
        return id
    }

    func test_resumePath_networkDownWithPart_keepsAttemptAndPart() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let (dir, part) = destWithPart(stem: "Clip")
        let runner = FakeProcessRunner()
        runner.script(
            .stderr(
                "ERROR: Unable to download webpage: Failed to resolve 'x' "
                    + "(nodename nor servname provided, or not known)",
                exitCode: 1
            ),
            forPathEndingIn: "yt-dlp"
        )
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = engine(runner, probe, clock: clock)
        let collector = EventCollector(engine.events)

        let id = await failedJob(engine, collector, clock, request: Fix.request(destFolder: dir))
        XCTAssertEqual(job(collector, id)?.state, .failed(.networkDown))
        let attemptBefore = job(collector, id)?.attempt ?? -1
        XCTAssertGreaterThan(attemptBefore, 0)

        await engine.retry(id)
        _ = await collector.waitForState(id) { $0 == .queued || $0 == .running }

        XCTAssertEqual(job(collector, id)?.attempt, attemptBefore, "resume keeps attempt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: part.path), ".part kept")
    }

    func test_retryPath_rateLimited_resetsAttemptDeletesPart() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let (dir, part) = destWithPart(stem: "Clip")
        let runner = FakeProcessRunner()
        runner.script(.stderr("ERROR: HTTP Error 429", exitCode: 1), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = engine(runner, probe, clock: clock)
        let collector = EventCollector(engine.events)

        let id = await failedJob(engine, collector, clock, request: Fix.request(destFolder: dir))
        XCTAssertEqual(job(collector, id)?.state, .failed(.rateLimited()))

        await engine.retry(id)
        _ = await collector.waitForState(id) { $0 == .queued || $0 == .running }

        XCTAssertEqual(job(collector, id)?.attempt, 0, "retry restores the full budget")
        XCTAssertFalse(FileManager.default.fileExists(atPath: part.path), ".part deleted")
    }

    func test_retryPath_incompleteWithNoPart_usesRetryClearsIntegrityFields() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-retry-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let short = dir.appendingPathComponent("Clip.mp4")
        FileManager.default.createFile(atPath: short.path, contents: Data("x".utf8))
        let runner = FakeProcessRunner()
        runner.script(
            Fix.completingScript([.stdout("[download] Destination: \(short.path)")]),
            forPathEndingIn: "yt-dlp"
        )
        runner.script(
            .stdout("{\"format\":{\"duration\":\"5\"},\"streams\":[]}", exitCode: 0),
            forPathEndingIn: "ffprobe"
        )
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip", durationSeconds: 600))
        let engine = engine(
            runner, probe, clock: clock,
            ffprobeURL: URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
        )
        let collector = EventCollector(engine.events)

        let id = await failedJob(engine, collector, clock, request: Fix.request(destFolder: dir))
        XCTAssertEqual(job(collector, id)?.state, .failed(.incomplete))
        XCTAssertNotNil(job(collector, id)?.integrityVerdict)

        await engine.retry(id)
        _ = await collector.waitForState(id) { $0 == .queued || $0 == .running }

        XCTAssertEqual(job(collector, id)?.attempt, 0)
        XCTAssertNil(job(collector, id)?.integrityVerdict, "integrity fields cleared on retry")
        XCTAssertNil(job(collector, id)?.actualQuality)
    }

    func test_noOpOnNonRetryableClass() async {
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

        await engine.retry(id)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(job(collector, id)?.state, .failed(.geoBlocked))
    }

    func test_noOpOnNonFailedJob() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(30)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = engine(runner, probe, clock: clock)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        _ = await collector.waitForState(id) { $0 == .running }

        await engine.retry(id)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(job(collector, id)?.state, .running)
    }
}
