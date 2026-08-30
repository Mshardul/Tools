@testable import GrabberKit
import TestSupport
import XCTest

final class DownloadEngineSchedulerTests: XCTestCase {
    private typealias Fix = EngineFixture

    func test_capOne_downloadsStrictlySequential() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .milliseconds(80)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe, cap: 1)
        let collector = EventCollector(engine.events)

        let first = await submitJob(engine, Fix.request(url: "https://archive.org/details/1"))
        let second = await submitJob(engine, Fix.request(url: "https://archive.org/details/2"))
        _ = await collector.waitForState(first) { $0 == .completed }
        _ = await collector.waitForState(second) { $0 == .completed }

        XCTAssertEqual(runner.maxConcurrent, 1)
    }

    func test_capTwo_twoConcurrent_thirdWaits() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .milliseconds(150)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe, cap: 2)
        let collector = EventCollector(engine.events)

        let jobA = await submitJob(engine, Fix.request(url: "https://archive.org/details/1"))
        let jobB = await submitJob(engine, Fix.request(url: "https://archive.org/details/2"))
        let jobC = await submitJob(engine, Fix.request(url: "https://archive.org/details/3"))

        _ = await collector.waitForState(jobA) { $0 == .running }
        _ = await collector.waitForState(jobB) { $0 == .running }
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(collector.latestSnapshot()?.jobs.first { $0.id == jobC }?.state, .queued)

        _ = await collector.waitForState(jobA) { $0 == .completed }
        _ = await collector.waitForState(jobB) { $0 == .completed }
        _ = await collector.waitForState(jobC) { $0 == .completed }
        XCTAssertEqual(runner.maxConcurrent, 2)
    }

    func test_burstOfThreeFreshURLs_pipelines() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .milliseconds(120)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.perProbeDelay = .milliseconds(30)
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe, cap: 2)
        let collector = EventCollector(engine.events)

        let jobA = await submitJob(engine, Fix.request(url: "https://archive.org/details/1"))
        let jobB = await submitJob(engine, Fix.request(url: "https://archive.org/details/2"))
        let jobC = await submitJob(engine, Fix.request(url: "https://archive.org/details/3"))

        _ = await collector.waitForState(jobA) { $0 == .completed }
        _ = await collector.waitForState(jobB) { $0 == .completed }
        _ = await collector.waitForState(jobC) { $0 == .completed }

        // All three probed and downloaded — the pipeline did not stall at one.
        XCTAssertEqual(Set(probe.probedURLs).count, 3)
        XCTAssertEqual(runner.launches.count, 3)
        XCTAssertEqual(runner.maxConcurrent, 2)
    }

    func test_loweredCapKillsNothing() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .milliseconds(200)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe, cap: 2)
        let collector = EventCollector(engine.events)

        let jobA = await submitJob(engine, Fix.request(url: "https://archive.org/details/1"))
        let jobB = await submitJob(engine, Fix.request(url: "https://archive.org/details/2"))
        _ = await collector.waitForState(jobA) { $0 == .running }
        _ = await collector.waitForState(jobB) { $0 == .running }
        await engine.setCap(1)

        _ = await collector.waitForState(jobA) { $0 == .completed }
        _ = await collector.waitForState(jobB) { $0 == .completed }
        XCTAssertEqual(runner.cancelledCount, 0)
    }

    func test_everyMutationRevisionStrictlyIncreases() async {
        let runner = FakeProcessRunner()
        runner.script(
            Fix.completingScript([Fix.progressLine(" 50.0%"), Fix.progressLine("100.0%")]),
            forPathEndingIn: "yt-dlp"
        )
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        _ = await collector.waitForState(id) { $0 == .completed }

        let revisions = collector.revisions()
        XCTAssertGreaterThan(revisions.count, 2)
        XCTAssertEqual(revisions, revisions.sorted())
        XCTAssertEqual(Set(revisions).count, revisions.count)
    }

    func test_progressLinesAreProgressEvents_stateChangesAreSnapshots() async {
        let runner = FakeProcessRunner()
        runner.script(
            Fix.completingScript([Fix.progressLine(" 50.0%")]),
            forPathEndingIn: "yt-dlp"
        )
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        _ = await collector.waitForState(id) { $0 == .completed }

        var sawProgressEvent = false
        var terminalIsSnapshot = false
        for event in collector.all {
            switch event {
            case let .progress(delta, _):
                sawProgressEvent = true
                XCTAssertEqual(Array(delta.keys), [id])
            case let .snapshot(snap):
                if snap.jobs.first(where: { $0.id == id })?.state == .completed {
                    terminalIsSnapshot = true
                }
            }
        }
        XCTAssertTrue(sawProgressEvent)
        XCTAssertTrue(terminalIsSnapshot)
    }

    func test_duplicateRequestInAnyState() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(30)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe)
        let collector = EventCollector(engine.events)

        let req = Fix.request()
        let id = await submitJob(engine, req)
        _ = await collector.waitForState(id) { $0 == .running }

        let second = await engine.submit(req, force: false, prefetchedMetadata: nil)
        guard case let .duplicateExists(existing, wasCompleted) = second else {
            return XCTFail("expected .duplicateExists")
        }
        XCTAssertEqual(existing, id)
        XCTAssertFalse(wasCompleted)
        XCTAssertEqual(collector.latestSnapshot()?.jobs.count, 1)
    }

    func test_forceTrue_createsDistinctJob() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(30)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe)
        let collector = EventCollector(engine.events)

        let req = Fix.request()
        let first = await submitJob(engine, req)
        _ = await collector.waitForState(first) { $0 == .running }

        let forced = await engine.submit(req, force: true, prefetchedMetadata: nil)
        guard case let .queued(secondID) = forced else { return XCTFail("expected .queued") }
        XCTAssertNotEqual(first, secondID)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(collector.latestSnapshot()?.jobs.count, 2)
    }

    func test_prefetchedMetadata_skipsProbing() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .milliseconds(60)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        let engine = Fix.engine(runner: runner, probe: probe)
        let collector = EventCollector(engine.events)

        let meta = MediaMetadata(
            title: "Prefetched", durationSeconds: 12, isPlaylist: false,
            sourceURL: "https://archive.org/details/x", extractor: "youtube"
        )
        let result = await engine.submit(Fix.request(), force: false, prefetchedMetadata: meta)
        guard case let .queued(id) = result else { return XCTFail("expected .queued") }
        _ = await collector.waitForState(id) { $0 == .completed }

        XCTAssertTrue(probe.probedURLs.isEmpty)
        let statesSeen = collector.snapshots.compactMap { snap in
            snap.jobs.first { $0.id == id }?.state
        }
        XCTAssertFalse(statesSeen.contains(.probing))
    }

    func test_sizeBytesFromFirstTotalBytes() async {
        let runner = FakeProcessRunner()
        runner.perLineDelay = .milliseconds(10)
        runner.script(
            Fix.completingScript([
                Fix.progressLine(" 25.0%", total: "5000"),
                Fix.progressLine(" 60.0%", total: "9999"),
                Fix.progressLine("100.0%", total: "9999")
            ]),
            forPathEndingIn: "yt-dlp"
        )
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        _ = await collector.waitForState(id) { $0 == .completed }

        XCTAssertEqual(collector.latestSnapshot()?.jobs.first { $0.id == id }?.sizeBytes, 5000)
    }
}
