@testable import GrabberKit
import TestSupport
import XCTest

final class DownloadEngineTests: XCTestCase {
    private typealias Fix = EngineFixture

    func test_submitReturnsQueuedImmediately() async {
        let runner = FakeProcessRunner()
        let probe = FakeMetadataProbe()
        probe.perProbeDelay = .milliseconds(200)
        let engine = Fix.engine(runner: runner, probe: probe)
        let collector = EventCollector(engine.events)

        let result = await engine.submit(Fix.request(), force: false, prefetchedMetadata: nil)

        guard case .queued = result else { return XCTFail("expected .queued") }
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(collector.snapshots.first?.jobs.first?.state, .queued)
        XCTAssertTrue(runner.launches.isEmpty)
    }

    func test_happyPath() async {
        let runner = FakeProcessRunner()
        runner.script(
            Fix.completingScript([
                Fix.progressLine(" 25.0%"),
                Fix.progressLine(" 60.0%"),
                Fix.progressLine("100.0%")
            ]),
            forPathEndingIn: "yt-dlp"
        )
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        await expectState(collector, id) { $0 == .completed }

        let job = collector.latestSnapshot()?.jobs.first { $0.id == id }
        XCTAssertEqual(job?.title, "Clip")
        XCTAssertEqual(job?.progress?.fraction, 1.0)
        XCTAssertNotNil(job?.finishedAt)
    }

    func test_stateSequence() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .milliseconds(40)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.perProbeDelay = .milliseconds(40)
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        await expectState(collector, id) { $0 == .completed }

        var seen: [JobState] = []
        for snap in collector.snapshots {
            if let state = snap.jobs.first(where: { $0.id == id })?.state, seen.last != state {
                seen.append(state)
            }
        }
        // The headline lifecycle appears in order; a metadata-arrival re-queue may sit between.
        XCTAssertTrue(
            isOrderedSubsequence([.queued, .probing, .running, .completed], of: seen),
            "\(seen)"
        )
        XCTAssertEqual(seen.first, .queued)
        XCTAssertEqual(seen.last, .completed)
    }

    // A single-retry budget with a FakeClock: after the one auto-retry the job goes terminal
    // with the classified ErrorClass.
    private func singleRetryEngine(
        runner: FakeProcessRunner,
        probe: FakeMetadataProbe,
        clock: FakeClock
    ) -> DownloadEngine {
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.maxAutoRetries = 1
        return DownloadEngine(
            dependencies: EngineDependencies(
                runner: runner,
                probe: probe,
                envProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
                clock: clock,
                ytDlpURL: Fix.ytDlp,
                jobLogDir: Fix.scratchLogDir(),
                debugFlags: EngineDebugFlags(concurrencyCapOverride: 1)
            ),
            preferences: prefs
        )
    }

    func test_nonZeroExit_networkStderr_failsNetworkDownAfterBudget() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let runner = FakeProcessRunner()
        runner.script(
            FakeProcessRunner.Script(
                lines: [.stderr(
                    "ERROR: Unable to download webpage: Failed to resolve 'x' "
                        + "(nodename nor servname provided, or not known)"
                )],
                exitCode: 1
            ),
            forPathEndingIn: "yt-dlp"
        )
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = singleRetryEngine(runner: runner, probe: probe, clock: clock)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        _ = await collector.waitForState(id) { $0 == .running }
        _ = await collector.waitForState(id) { $0 == .queued }
        for _ in 0 ..< 3 {
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
        XCTAssertEqual(
            collector.latestSnapshot()?.jobs.first { $0.id == id }?.state,
            .failed(.networkDown)
        )
    }

    func test_nonZeroExit_noSignature_failsUnknownAfterBudget() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let runner = FakeProcessRunner()
        runner.script(.stdout("", exitCode: 3), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = singleRetryEngine(runner: runner, probe: probe, clock: clock)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        _ = await collector.waitForState(id) { $0 == .running }
        _ = await collector.waitForState(id) { $0 == .queued }
        for _ in 0 ..< 3 {
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
        guard case let .failed(.unknown(raw)) = collector.latestSnapshot()?.jobs
            .first(where: { $0.id == id })?.state
        else {
            return XCTFail("expected .failed(.unknown)")
        }
        XCTAssertTrue(raw.contains("3"))
    }

    func test_probeNetworkFailure_failsBeforeSpawn() async {
        let runner = FakeProcessRunner()
        let probe = FakeMetadataProbe()
        probe.result(.failure(.network))
        let engine = Fix.engine(runner: runner, probe: probe)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        await expectState(collector, id) { $0 == .failed(.networkDown) }
        XCTAssertTrue(runner.launches.isEmpty)
    }

    func test_probeYtDlpMissing_failsDepMissing() async {
        let runner = FakeProcessRunner()
        let probe = FakeMetadataProbe()
        probe.result(.failure(.ytDlpMissing))
        let engine = Fix.engine(runner: runner, probe: probe)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        await expectState(collector, id) { $0 == .failed(.depMissing) }
        XCTAssertTrue(runner.launches.isEmpty)
    }

    func test_cancel_killsChild_setsCancelled() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(30)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        _ = await collector.waitForState(id) { $0 == .running }
        await engine.cancel(id)
        await expectState(collector, id) { $0 == .cancelled }

        XCTAssertEqual(runner.cancelledCount, 1)
        XCTAssertNotNil(collector.latestSnapshot()?.jobs.first { $0.id == id }?.finishedAt)
    }

    func test_outputFilesResolvedOnCompletion() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-engine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("x".utf8).write(to: dir.appendingPathComponent("Clip.mp4"))

        let runner = FakeProcessRunner()
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request(destFolder: dir))
        await expectState(collector, id) { $0 == .completed }
        XCTAssertEqual(
            collector.latestSnapshot()?.jobs.first { $0.id == id }?.outputFiles
                .map(\.lastPathComponent),
            ["Clip.mp4"]
        )
    }

    func test_outputFilesCapturedFromDestination_whenTitleSanitized() async throws {
        let title = "RASTAFARIANESIMO： La Religione che Venera la Pianta della Conoscenza 🇯🇲"
        let fileName = "RASTAFARIANESIMO La Religione che Venera la Pianta della Conoscenza.mp4"
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-engine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let outputURL = dir.appendingPathComponent(fileName)
        try Data("x".utf8).write(to: outputURL)

        let runner = FakeProcessRunner()
        runner.script(
            Fix.completingScript([
                .stdout("[download] Destination: \(outputURL.path)")
            ]),
            forPathEndingIn: "yt-dlp"
        )
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: title))
        let engine = Fix.engine(runner: runner, probe: probe)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request(destFolder: dir))
        await expectState(collector, id) { $0 == .completed }
        XCTAssertEqual(
            collector.latestSnapshot()?.jobs.first { $0.id == id }?.outputFiles,
            [outputURL]
        )
    }
}
