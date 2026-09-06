@testable import GrabberKit
import TestSupport
import XCTest

final class EngineRateLimitTests: XCTestCase {
    private typealias Fix = EngineFixture

    private func job(_ collector: EventCollector, _ id: UUID) -> JobSnapshot? {
        collector.latestSnapshot()?.jobs.first { $0.id == id }
    }

    private func isCooldown(_ state: JobState?) -> Bool {
        if case .cooldown = state {
            return true
        }
        return false
    }

    private func isFailed(_ state: JobState?) -> Bool {
        if case .failed = state {
            return true
        }
        return false
    }

    private let rl429 = FakeProcessRunner.Script.stderr(
        "ERROR: HTTP Error 429: Too Many Requests", exitCode: 1
    )

    private func successProbe() -> FakeMetadataProbe {
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        return probe
    }

    func testRateLimitedExitStrikesHostAndCoolsTheJob() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1000))
        let runner = FakeProcessRunner()
        runner.script(rl429, forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(runner: runner, probe: successProbe(), cap: 1, clock: clock)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=x"))
        _ = await collector.waitForState(id) { self.isCooldown($0) }

        let adaptive = await engine.adaptiveCapForTest()
        XCTAssertNotNil(job(collector, id)?.cooldownUntil)
        XCTAssertEqual(job(collector, id)?.attempt, 1)
        XCTAssertEqual(adaptive, 1)
        XCTAssertEqual(collector.latestSnapshot()?.hostRateSummary.count, 1)
    }

    func testSecondQueuedJobForSameHostIsBlockedNotMutated() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1000))
        let runner = FakeProcessRunner()
        runner.script(rl429, forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(runner: runner, probe: successProbe(), cap: 2, clock: clock)
        let collector = EventCollector(engine.events)

        let first = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=a"))
        let second = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=b"))
        _ = await collector.waitForState(first) { self.isCooldown($0) }
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(job(collector, second)?.state, .queued)
    }

    func testTwoInFlightBothFailOnlyOneCools() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1000))
        let runner = FakeProcessRunner()
        runner.script(rl429, forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(runner: runner, probe: successProbe(), cap: 2, clock: clock)
        let collector = EventCollector(engine.events)

        let first = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=a"))
        let second = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=b"))
        _ = await collector.waitForState(first) { self.isCooldown($0) || self.isFailed($0) }
        _ = await collector.waitForState(second) { $0 != .running && $0 != .probing }
        try? await Task.sleep(for: .milliseconds(50))

        let cooling = collector.latestSnapshot()?.jobs.filter { self.isCooldown($0.state) } ?? []
        XCTAssertLessThanOrEqual(cooling.count, 1)
    }

    func testNonRateLimitFailureDoesNotTouchHostState() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let runner = FakeProcessRunner()
        runner.script(
            .stderr("ERROR: unable to write data: No space left on device", exitCode: 1),
            forPathEndingIn: "yt-dlp"
        )
        let engine = Fix.engine(runner: runner, probe: successProbe(), cap: 3, clock: clock)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=x"))
        _ = await collector.waitForState(id) { self.isFailed($0) }

        let adaptive = await engine.adaptiveCapForTest()
        XCTAssertEqual(collector.latestSnapshot()?.hostRateSummary.isEmpty, true)
        XCTAssertEqual(adaptive, EngineTuning.default.adaptiveConcurrencyStart)
    }

    func testTerminalRateLimitedStillStrikes() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1000))
        let runner = FakeProcessRunner()
        runner.script(rl429, forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(
            runner: runner, probe: successProbe(), cap: 1, clock: clock,
            tuning: EngineTuning.resolved(environment: ["MG_BACKOFF_LADDER": "1"]),
            maxAutoRetries: 1
        )
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=x"))
        _ = await collector.waitForState(id) { self.isCooldown($0) }
        clock.advance(by: .seconds(2))
        try? await Task.sleep(for: .milliseconds(30))
        _ = await collector.waitForState(id) { self.isFailed($0) }

        XCTAssertEqual(collector.latestSnapshot()?.hostRateSummary.isEmpty, false)
    }

    func testLaunchUsesThrottledFragmentsForCoolingHost() async throws {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1000))
        let runner = FakeProcessRunner()
        runner.scripts([rl429, FakeProcessRunner.Script(exitCode: 0)], forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(
            runner: runner, probe: successProbe(), cap: 1, clock: clock,
            tuning: EngineTuning.resolved(environment: ["MG_BACKOFF_LADDER": "1"])
        )
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=x"))
        _ = await collector.waitForState(id) { self.isCooldown($0) }
        clock.advance(by: .seconds(2))
        try? await Task.sleep(for: .milliseconds(60))

        let ytLaunches = runner.launches.filter { $0.executableURL.lastPathComponent == "yt-dlp" }
        XCTAssertGreaterThanOrEqual(ytLaunches.count, 2)

        let firstArgs = ytLaunches[0].arguments
        let firstFlag = try XCTUnwrap(firstArgs.firstIndex(of: "--concurrent-fragments"))
        XCTAssertEqual(firstArgs[firstArgs.index(after: firstFlag)], "4")

        let retryArgs = ytLaunches[1].arguments
        let retryFlag = try XCTUnwrap(retryArgs.firstIndex(of: "--concurrent-fragments"))
        XCTAssertEqual(retryArgs[retryArgs.index(after: retryFlag)], "1")
    }

    func testCleanCompletionResetsHostAndRampsCap() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1000))
        let runner = FakeProcessRunner()
        runner.scripts([rl429, FakeProcessRunner.Script(exitCode: 0)], forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(
            runner: runner, probe: successProbe(), cap: 3, clock: clock,
            tuning: EngineTuning.resolved(environment: ["MG_BACKOFF_LADDER": "1"])
        )
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=x"))
        _ = await collector.waitForState(id) { self.isCooldown($0) }
        clock.advance(by: .seconds(2))
        try? await Task.sleep(for: .milliseconds(30))
        _ = await collector.waitForState(id) { $0 == .completed }

        XCTAssertEqual(collector.latestSnapshot()?.hostRateSummary.isEmpty, true)
    }
}
