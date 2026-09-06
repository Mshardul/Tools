@testable import GrabberKit
import TestSupport
import XCTest

final class EngineNetworkTests: XCTestCase {
    private typealias Fix = EngineFixture

    private func longRunner(exitCode: Int32 = 0) -> FakeProcessRunner {
        let runner = FakeProcessRunner()
        runner.perLineDelay = .milliseconds(500)
        runner.script(
            FakeProcessRunner.Script(
                lines: [Fix.progressLine("10"), Fix.progressLine("50"), Fix.progressLine("90")],
                exitCode: exitCode
            ),
            forPathEndingIn: "yt-dlp"
        )
        return runner
    }

    private func job(_ collector: EventCollector, _ id: UUID) -> JobSnapshot? {
        collector.latestSnapshot()?.jobs.first { $0.id == id }
    }

    private func successProbe() -> FakeMetadataProbe {
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        return probe
    }

    func testOfflineHaltsAndParksRunningJobs() async {
        let net = FakeNetworkMonitor(startOnline: true)
        let engine = Fix.engine(
            runner: longRunner(), probe: successProbe(), cap: 2, networkMonitor: net
        )
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request())
        _ = await collector.waitForState(id) { $0 == .running }

        net.goOffline()
        _ = await collector.waitForState(id) { $0 == .waitingForNetwork }

        XCTAssertEqual(collector.latestSnapshot()?.queueHalt, .networkDown)
        XCTAssertEqual(collector.latestSnapshot()?.isOnline, false)
        XCTAssertEqual(job(collector, id)?.attempt, 0)
    }

    func testOnlineResumesWithoutBurningAttempt() async {
        let net = FakeNetworkMonitor(startOnline: true)
        let runner = FakeProcessRunner()
        runner.perLineDelay = .milliseconds(300)
        let firstScript = FakeProcessRunner.Script(
            lines: [Fix.progressLine("10"), Fix.progressLine("50")], exitCode: 0
        )
        runner.scripts([firstScript, FakeProcessRunner.Script(exitCode: 0)], forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(
            runner: runner, probe: successProbe(), cap: 2, networkMonitor: net
        )
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request())
        _ = await collector.waitForState(id) { $0 == .running }

        net.goOffline()
        _ = await collector.waitForState(id) { $0 == .waitingForNetwork }
        net.goOnline()
        _ = await collector.waitForState(id) { $0 != .waitingForNetwork }

        XCTAssertNil(collector.latestSnapshot()?.queueHalt)
        XCTAssertEqual(collector.latestSnapshot()?.isOnline, true)
        XCTAssertEqual(job(collector, id)?.attempt, 0)
    }

    func testQueuedJobsStayQueuedOnOffline() async {
        let net = FakeNetworkMonitor(startOnline: true)
        let engine = Fix.engine(
            runner: longRunner(), probe: successProbe(), cap: 1, networkMonitor: net
        )
        let collector = EventCollector(engine.events)
        let first = await submitJob(engine, Fix.request(url: "https://a.test/1"))
        let second = await submitJob(engine, Fix.request(url: "https://b.test/2"))
        _ = await collector.waitForState(first) { $0 == .running }
        _ = await collector.waitForState(second) { $0 == .queued }

        net.goOffline()
        try? await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(job(collector, second)?.state, .queued)
    }

    func testParkedJobsKeepTheQuitPromptAlive() async {
        let net = FakeNetworkMonitor(startOnline: true)
        let engine = Fix.engine(
            runner: longRunner(), probe: successProbe(), cap: 2, networkMonitor: net
        )
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request())
        _ = await collector.waitForState(id) { $0 == .running }

        net.goOffline()
        _ = await collector.waitForState(id) { $0 == .waitingForNetwork }

        let active = await engine.hasActiveJobs()
        XCTAssertTrue(active)
    }
}
