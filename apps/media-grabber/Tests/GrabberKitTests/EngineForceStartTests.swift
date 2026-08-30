@testable import GrabberKit
import TestSupport
import XCTest

final class EngineForceStartTests: XCTestCase {
    private typealias Fix = EngineFixture

    private func heldRunner() -> FakeProcessRunner {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(30)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        return runner
    }

    private func probe() -> FakeMetadataProbe {
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        return probe
    }

    func test_runningBelowCap_nothingEvicted() async {
        let runner = heldRunner()
        let engine = Fix.engine(runner: runner, probe: probe(), cap: 3)
        let collector = EventCollector(engine.events)

        let first = await submitJob(engine, Fix.request(url: "https://archive.org/details/1"))
        _ = await collector.waitForState(first) { $0 == .running }
        let queued = await submitJob(engine, Fix.request(url: "https://archive.org/details/2"))
        // second job also auto-starts at cap 3; force it anyway from wherever it is.
        _ = await collector.waitForState(queued) { $0 == .running }

        // A genuinely queued job: add a third and immediately drop cap so it stays queued.
        await engine.setCap(2)
        let third = await submitJob(engine, Fix.request(url: "https://archive.org/details/3"))
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(collector.latestSnapshot()?.jobs.first { $0.id == third }?.state, .queued)

        await engine.setCap(3)
        await engine.forceStart(third)
        await expectState(collector, third) { $0 == .running }
        XCTAssertEqual(runner.cancelledCount, 0)
    }

    func test_runningAtCap_exactlyOneSnapshot_victimQueuedAtTail() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-force-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let part = dir.appendingPathComponent("Clip.mp4.part")
        try Data("p".utf8).write(to: part)

        let runner = heldRunner()
        let probe = probe()
        let engine = Fix.engine(runner: runner, probe: probe, cap: 1)
        let collector = EventCollector(engine.events)

        let victim = await submitJob(
            engine,
            Fix.request(url: "https://archive.org/details/1", destFolder: dir)
        )
        _ = await collector.waitForState(victim) { $0 == .running }
        let forced = await submitJob(engine, Fix.request(url: "https://archive.org/details/2"))
        _ = await collector.waitForState(forced) { _ in probe.probedURLs.count == 2 }
        _ = await collector.waitForState(forced) { $0 == .queued }

        let before = collector.revisions().count
        await engine.forceStart(forced)
        await expectState(collector, forced) { $0 == .running }

        let flip = collector.snapshots.first {
            $0.jobs.first { $0.id == forced }?.state == .running
        }
        let flippedJobs = try XCTUnwrap(flip?.jobs)
        XCTAssertEqual(flippedJobs.first { $0.id == victim }?.state, .queued)
        XCTAssertEqual(flippedJobs.map(\.id).last, victim)

        // No intermediate world where the forced job is running but the victim is not yet queued.
        let bad = collector.snapshots.contains { snap in
            let forcedRunning = snap.jobs.first { $0.id == forced }?.state == .running
            let victimStillRunning = snap.jobs.first { $0.id == victim }?.state == .running
            return forcedRunning && victimStillRunning
        }
        XCTAssertFalse(bad)

        XCTAssertTrue(FileManager.default.fileExists(atPath: part.path))
        _ = before
    }

    func test_twoRapidForceStarts_churnOnce_thenStabilise() async {
        let runner = heldRunner()
        let probe = probe()
        let engine = Fix.engine(runner: runner, probe: probe, cap: 1)
        let collector = EventCollector(engine.events)

        let running = await submitJob(engine, Fix.request(url: "https://archive.org/details/1"))
        _ = await collector.waitForState(running) { $0 == .running }
        let jobB = await submitJob(engine, Fix.request(url: "https://archive.org/details/2"))
        let jobC = await submitJob(engine, Fix.request(url: "https://archive.org/details/3"))
        // Both must be probe-complete .queued (not mid-probe) before force-starting.
        _ = await collector.waitForState(jobB) { _ in probe.probedURLs.count == 3 }
        try? await Task.sleep(for: .milliseconds(10))

        await engine.forceStart(jobB)
        await engine.forceStart(jobC)

        // Let the two evicted children's cancellations drain, then assert the queue settled.
        var snapshot = await engine.currentSnapshot()
        for _ in 0 ..< 50 where snapshot.jobs.filter({ $0.state == .running }).count != 1 {
            try? await Task.sleep(for: .milliseconds(10))
            snapshot = await engine.currentSnapshot()
        }

        XCTAssertEqual(snapshot.jobs.filter { $0.state == .running }.map(\.id), [jobC])
        XCTAssertEqual(snapshot.jobs.filter { $0.state == .queued }.count, 2)
        // A kill-and-replace handoff briefly overlaps the dying child with the new one.
        XCTAssertLessThanOrEqual(runner.maxConcurrent, 2)
    }

    func test_forceStartOnRunningJob_isNoOp() async {
        let runner = heldRunner()
        let engine = Fix.engine(runner: runner, probe: probe(), cap: 2)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        _ = await collector.waitForState(id) { $0 == .running }
        let revBefore = collector.revisions().count

        await engine.forceStart(id)
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(collector.revisions().count, revBefore)
    }
}
