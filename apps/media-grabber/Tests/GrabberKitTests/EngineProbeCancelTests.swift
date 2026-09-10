@testable import GrabberKit
import TestSupport
import XCTest

final class EngineProbeCancelTests: XCTestCase {
    private typealias Fix = EngineFixture

    func testCancelWhileProbingLeavesJobCancelledAfterProbeReturns() async {
        let runner = FakeProcessRunner()
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = CancellationObservingMetadataProbe()
        let engine = Fix.engine(runner: runner, probe: probe)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        let reachedProbing = await collector.waitForState(id) { $0 == .probing }
        XCTAssertTrue(reachedProbing)
        let probeStarted = await probe.waitUntilStarted()
        XCTAssertTrue(probeStarted)

        await engine.cancel(id)
        let probeCancelled = await probe.waitUntilCancelled()
        XCTAssertTrue(probeCancelled)
        let reachedCancelled = await collector.waitForState(id) { $0 == .cancelled }
        XCTAssertTrue(reachedCancelled)
        try? await Task.sleep(for: .milliseconds(40))

        let snapshot = await engine.currentSnapshot()
        let job = snapshot.jobs.first { $0.id == id }
        XCTAssertEqual(job?.state, .cancelled)
        XCTAssertNotNil(job?.finishedAt)
        XCTAssertTrue(runner.launches.isEmpty)
    }

    func testRemoveWhileProbingKeepsJobRemovedAfterProbeReturns() async {
        let runner = FakeProcessRunner()
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = CancellationObservingMetadataProbe()
        let engine = Fix.engine(runner: runner, probe: probe)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        let reachedProbing = await collector.waitForState(id) { $0 == .probing }
        XCTAssertTrue(reachedProbing)
        let probeStarted = await probe.waitUntilStarted()
        XCTAssertTrue(probeStarted)

        await engine.remove(id)
        let probeCancelled = await probe.waitUntilCancelled()
        XCTAssertTrue(probeCancelled)
        try? await Task.sleep(for: .milliseconds(40))

        let snapshot = await engine.currentSnapshot()
        XCTAssertNil(snapshot.jobs.first { $0.id == id })
        XCTAssertTrue(runner.launches.isEmpty)
    }

    func testRecordProbeResultIgnoresNonProbingJob() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(30)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        let engine = Fix.engine(runner: runner, probe: probe)
        let collector = EventCollector(engine.events)
        let metadata = MediaMetadata(
            title: "Prefetched",
            durationSeconds: 10,
            isPlaylist: false,
            sourceURL: "",
            extractor: "archive"
        )

        let result = await engine.submit(
            Fix.request(),
            force: false,
            prefetchedMetadata: metadata
        )
        guard case let .queued(id) = result else {
            return XCTFail("expected .queued")
        }
        let reachedRunning = await collector.waitForState(id) { $0 == .running }
        XCTAssertTrue(reachedRunning)

        await engine.recordProbeResult(id, FakeMetadataProbe.success(title: "Late Probe"))
        try? await Task.sleep(for: .milliseconds(40))

        let snapshot = await engine.currentSnapshot()
        let job = snapshot.jobs.first { $0.id == id }
        XCTAssertEqual(job?.state, .running)
        XCTAssertEqual(job?.title, "Prefetched")
        XCTAssertEqual(runner.launches.count, 1)
    }
}

private final class CancellationObservingMetadataProbe: MetadataProbing, @unchecked Sendable {
    private struct State {
        var started = false
        var cancelled = false
    }

    private let box = LockedBox(State())

    func probe(_: String, context _: ExtractorContext) async -> Result<MediaMetadata, MetadataError> {
        box.mutate { $0.started = true }
        do {
            try await withTaskCancellationHandler {
                try await Task.sleep(for: .seconds(30))
            } onCancel: {
                self.box.mutate { $0.cancelled = true }
            }
        } catch {
            box.mutate { $0.cancelled = true }
        }
        return FakeMetadataProbe.success(title: "Late Probe")
    }

    func probePlaylist(
        _: String,
        context _: ExtractorContext
    ) async -> Result<PlaylistDump, MetadataError> {
        .failure(.malformedOutput)
    }

    func waitUntilStarted(timeout: TimeInterval = 5) async -> Bool {
        await wait(timeout: timeout) {
            self.box.read(\.started)
        }
    }

    func waitUntilCancelled(timeout: TimeInterval = 5) async -> Bool {
        await wait(timeout: timeout) {
            self.box.read(\.cancelled)
        }
    }

    private func wait(timeout: TimeInterval, predicate: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}
