@testable import GrabberKit
import TestSupport
import XCTest

final class EngineHaltTests: XCTestCase {
    private typealias Fix = EngineFixture

    private func engine(
        runner: FakeProcessRunner,
        probe: FakeMetadataProbe,
        envProbe: FakeEnvironmentProbe
    ) -> DownloadEngine {
        DownloadEngine(
            dependencies: EngineDependencies(
                runner: runner,
                probe: probe,
                envProbe: envProbe,
                ytDlpURL: Fix.ytDlp,
                jobLogDir: Fix.scratchLogDir(),
                debugFlags: EngineDebugFlags(concurrencyCapOverride: 2)
            ),
            preferences: Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        )
    }

    private func launchFailureScript() -> FakeProcessRunner.Script {
        FakeProcessRunner.Script(
            lines: [.stderr("launch failed: The file doesn’t exist.")],
            exitCode: 127
        )
    }

    func test_depMissingFailure_haltsQueue() async {
        let runner = FakeProcessRunner()
        runner.script(launchFailureScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = engine(
            runner: runner,
            probe: probe,
            envProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true))
        )
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        let halted = await collector.waitForState(id) { _ in
            collector.latestSnapshot()?.queueHalt == .depMissing
        }
        XCTAssertTrue(halted)

        let snapshot = await engine.currentSnapshot()
        XCTAssertEqual(snapshot.queueHalt, .depMissing)
        XCTAssertEqual(snapshot.jobs.first { $0.id == id }?.state, .queued)

        let launchesAfterHalt = runner.launches.count
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(runner.launches.count, launchesAfterHalt)
    }

    func test_depMissingProbeFailure_classifiesSame() async {
        let runner = FakeProcessRunner()
        let probe = FakeMetadataProbe()
        probe.result(.failure(.launchFailed))
        let engine = engine(
            runner: runner,
            probe: probe,
            envProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true))
        )
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        let halted = await collector.waitForState(id) { _ in
            collector.latestSnapshot()?.queueHalt == .depMissing
        }
        XCTAssertTrue(halted)
        XCTAssertEqual(collector.latestSnapshot()?.jobs.first { $0.id == id }?.state, .queued)
        XCTAssertTrue(runner.launches.isEmpty)
    }

    func test_revalidateWithDepsPresent_clearsHalt_resumesQueue() async {
        let runner = FakeProcessRunner()
        let probe = FakeMetadataProbe()
        probe.result(.failure(.launchFailed))
        let envProbe = FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true))
        let engine = engine(runner: runner, probe: probe, envProbe: envProbe)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        _ = await collector.waitForState(id) { _ in
            collector.latestSnapshot()?.queueHalt == .depMissing
        }

        // Deps are back; the probe now succeeds so the requeued job can run.
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        await engine.revalidate()

        await expectState(collector, id) { $0 == .completed }
        XCTAssertNil(collector.latestSnapshot()?.queueHalt)
    }

    func test_revalidateWithDepsMissing_haltStands() async {
        let runner = FakeProcessRunner()
        let probe = FakeMetadataProbe()
        probe.result(.failure(.launchFailed))
        let envProbe = FakeEnvironmentProbe(.with(ytDlp: false, ffmpeg: false))
        let engine = engine(runner: runner, probe: probe, envProbe: envProbe)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        _ = await collector.waitForState(id) { _ in
            collector.latestSnapshot()?.queueHalt == .depMissing
        }

        await engine.revalidate()
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(collector.latestSnapshot()?.queueHalt, .depMissing)
        _ = id
    }
}
