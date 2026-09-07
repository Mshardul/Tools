@testable import GrabberKit
import TestSupport
import XCTest

final class EngineCircuitTests: XCTestCase {
    private typealias Fix = EngineFixture

    private let rl429 = FakeProcessRunner.Script.stderr(
        "ERROR: HTTP Error 429: Too Many Requests", exitCode: 1
    )

    private func job(_ collector: EventCollector, _ id: UUID) -> JobSnapshot? {
        collector.latestSnapshot()?.jobs.first { $0.id == id }
    }

    private func isCooldown(_ state: JobState?) -> Bool {
        if case .cooldown = state {
            return true
        }
        return false
    }

    private func successProbe() -> FakeMetadataProbe {
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        return probe
    }

    private func circuitEngine(
        _ runner: FakeProcessRunner, _ probe: FakeMetadataProbe, _ clock: FakeClock, cap: Int = 1
    ) -> DownloadEngine {
        Fix.engine(
            runner: runner, probe: probe, cap: cap, clock: clock,
            tuning: EngineTuning.resolved(environment: [
                "MG_CIRCUIT_STRIKE_THRESHOLD": "2", "MG_BACKOFF_LADDER": "1"
            ])
        )
    }

    func testCircuitTripsAndSetsDerivedHalt() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1000))
        let runner = FakeProcessRunner()
        runner.script(rl429, forPathEndingIn: "yt-dlp")
        let engine = circuitEngine(runner, successProbe(), clock)
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=x"))

        _ = await collector.waitForState(id) { self.isCooldown($0) }
        clock.advance(by: .seconds(2))
        try? await Task.sleep(for: .milliseconds(40))
        try? await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(collector.latestSnapshot()?.queueHalt, .circuitOpen)
        XCTAssertEqual(collector.latestSnapshot()?.hostRateSummary.count, 1)
        XCTAssertEqual(job(collector, id)?.state, .queued)
    }

    func testResetAllCircuitsClears() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1000))
        let runner = FakeProcessRunner()
        runner.scripts([rl429, rl429, FakeProcessRunner.Script(exitCode: 0)], forPathEndingIn: "yt-dlp")
        let engine = circuitEngine(runner, successProbe(), clock)
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=x"))
        _ = await collector.waitForState(id) { self.isCooldown($0) }
        clock.advance(by: .seconds(2))
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(collector.latestSnapshot()?.queueHalt, .circuitOpen)

        await engine.resetAllCircuits()
        try? await Task.sleep(for: .milliseconds(40))

        XCTAssertNil(collector.latestSnapshot()?.queueHalt)
        _ = await collector.waitForState(id) { $0 == .completed }
    }

    func testRevalidateDoesNotClearACircuit() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1000))
        let runner = FakeProcessRunner()
        runner.script(rl429, forPathEndingIn: "yt-dlp")
        let engine = circuitEngine(runner, successProbe(), clock)
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=x"))
        _ = await collector.waitForState(id) { self.isCooldown($0) }
        clock.advance(by: .seconds(2))
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(collector.latestSnapshot()?.queueHalt, .circuitOpen)

        await engine.revalidate()
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(collector.latestSnapshot()?.queueHalt, .circuitOpen)
    }

    func testForceStartOverridesCooldownWithoutResettingHost() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1000))
        let runner = FakeProcessRunner()
        runner.scripts([rl429, FakeProcessRunner.Script(exitCode: 0)], forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(runner: runner, probe: successProbe(), cap: 1, clock: clock)
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=x"))
        let cooled = await collector.waitForState(id) { self.isCooldown($0) }
        XCTAssertTrue(cooled)
        XCTAssertEqual(collector.latestSnapshot()?.hostRateSummary.isEmpty, false)

        runner.perRunDelay = .seconds(30)
        await engine.forceStart(id)
        let snap = await engine.currentSnapshot()
        XCTAssertEqual(snap.jobs.first { $0.id == id }?.state, .running)
        XCTAssertEqual(snap.hostRateSummary.isEmpty, false)
    }
}
