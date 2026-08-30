@testable import GrabberKit
import TestSupport
import XCTest

final class EngineDeferralTests: XCTestCase {
    private typealias Fix = EngineFixture

    private func engine(
        clock: FakeClock,
        runner: FakeProcessRunner,
        probe: FakeMetadataProbe,
        cap: Int = 1
    ) -> DownloadEngine {
        DownloadEngine(
            dependencies: EngineDependencies(
                runner: runner,
                probe: probe,
                envProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
                clock: clock,
                ytDlpURL: Fix.ytDlp,
                jobLogDir: Fix.scratchLogDir(),
                debugFlags: EngineDebugFlags(concurrencyCapOverride: cap)
            ),
            preferences: Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        )
    }

    // Submits a placeholder that occupies the single slot, plus the deferral target which
    // stays .queued. Returns (blockerID, targetID).
    private func blockedTarget(
        _ engine: DownloadEngine,
        _ collector: EventCollector,
        _ probe: FakeMetadataProbe
    ) async -> (UUID, UUID) {
        let blocker = await submitJob(engine, Fix.request(url: "https://archive.org/details/block"))
        _ = await collector.waitForState(blocker) { $0 == .running }
        let target = await submitJob(engine, Fix.request(url: "https://archive.org/details/target"))
        _ = await collector.waitForState(target) { _ in probe.probedURLs.count == 2 }
        _ = await collector.waitForState(target) { $0 == .queued }
        return (blocker, target)
    }

    private func heldRunner() -> FakeProcessRunner {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(30)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        return runner
    }

    private func probedJob(_ probe: FakeMetadataProbe) {
        probe.result(FakeMetadataProbe.success(title: "Clip"))
    }

    func test_deferredJobStartsOnlyAfterDeadline() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let runner = heldRunner()
        let probe = FakeMetadataProbe()
        probedJob(probe)
        let engine = engine(clock: clock, runner: runner, probe: probe)
        let collector = EventCollector(engine.events)

        let (blocker, target) = await blockedTarget(engine, collector, probe)
        await engine.deferStartForTest(target, until: Date(timeIntervalSince1970: 10))
        await engine.cancel(blocker)
        _ = await collector.waitForState(blocker) { $0 == .cancelled }

        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(collector.latestSnapshot()?.jobs.first { $0.id == target }?.state, .queued)

        clock.advance(by: .seconds(10))
        await expectState(collector, target) { $0 == .running }
    }

    func test_earliestDeadlineWakesFirst() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let runner = heldRunner()
        let probe = FakeMetadataProbe()
        probedJob(probe)
        let engine = engine(clock: clock, runner: runner, probe: probe, cap: 0)
        let collector = EventCollector(engine.events)

        let near = await submitJob(engine, Fix.request(url: "https://archive.org/details/1"))
        let far = await submitJob(engine, Fix.request(url: "https://archive.org/details/2"))
        _ = await collector.waitForState(near) { _ in probe.probedURLs.count == 2 }
        _ = await collector.waitForState(near) { $0 == .queued }
        _ = await collector.waitForState(far) { $0 == .queued }

        await engine.deferStartForTest(near, until: Date(timeIntervalSince1970: 5))
        await engine.deferStartForTest(far, until: Date(timeIntervalSince1970: 20))
        await engine.setCap(3)

        clock.advance(by: .seconds(5))
        await expectState(collector, near) { $0 == .running }
        XCTAssertEqual(collector.latestSnapshot()?.jobs.first { $0.id == far }?.state, .queued)
    }

    func test_nearerDeadlineReArms() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let runner = heldRunner()
        let probe = FakeMetadataProbe()
        probedJob(probe)
        let engine = engine(clock: clock, runner: runner, probe: probe)
        let collector = EventCollector(engine.events)

        let (blocker, target) = await blockedTarget(engine, collector, probe)
        await engine.deferStartForTest(target, until: Date(timeIntervalSince1970: 100))
        await engine.deferStartForTest(target, until: Date(timeIntervalSince1970: 5))
        await engine.cancel(blocker)

        clock.advance(by: .seconds(5))
        await expectState(collector, target) { $0 == .running }
    }

    func test_emptiedListSuspendsTask() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let runner = heldRunner()
        let probe = FakeMetadataProbe()
        probedJob(probe)
        let engine = engine(clock: clock, runner: runner, probe: probe)
        let collector = EventCollector(engine.events)

        let (blocker, target) = await blockedTarget(engine, collector, probe)
        await engine.deferStartForTest(target, until: Date(timeIntervalSince1970: 5))
        await engine.cancel(blocker)
        clock.advance(by: .seconds(5))
        await expectState(collector, target) { $0 == .running }

        let revBefore = collector.revisions().count
        clock.advance(by: .seconds(100))
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(collector.revisions().count, revBefore)
    }

    func test_shutdownCancelsIt() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let runner = heldRunner()
        let probe = FakeMetadataProbe()
        probedJob(probe)
        let engine = engine(clock: clock, runner: runner, probe: probe)
        let collector = EventCollector(engine.events)

        let (_, target) = await blockedTarget(engine, collector, probe)
        await engine.deferStartForTest(target, until: Date(timeIntervalSince1970: 1_000_000))

        let deadline = Date().addingTimeInterval(3)
        await engine.shutdown()
        XCTAssertLessThan(Date(), deadline)
    }
}
