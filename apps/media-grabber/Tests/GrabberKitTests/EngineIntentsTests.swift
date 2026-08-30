@testable import GrabberKit
import TestSupport
import XCTest

final class EngineIntentsTests: XCTestCase {
    private typealias Fix = EngineFixture

    private func tempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-intents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writePart(_ dir: URL, stem: String = "Clip") throws -> URL {
        let url = dir.appendingPathComponent("\(stem).mp4.part")
        try Data("partial".utf8).write(to: url)
        return url
    }

    private func engineWithLogSink(
        runner: FakeProcessRunner,
        probe: FakeMetadataProbe,
        cap: Int,
        onDeleteLog: @escaping @Sendable (UUID) -> Void
    ) throws -> DownloadEngine {
        let deps = EngineDependencies(
            runner: runner,
            probe: probe,
            envProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
            ytDlpURL: Fix.ytDlp,
            jobLogDir: Fix.scratchLogDir(),
            debugFlags: EngineDebugFlags(concurrencyCapOverride: cap),
            deleteJobLog: onDeleteLog
        )
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        return DownloadEngine(dependencies: deps, preferences: Preferences(defaults: defaults))
    }

    func test_pauseRunningJob_freesSlotForQueued() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(30)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe, cap: 1)
        let collector = EventCollector(engine.events)

        let first = await submitJob(engine, Fix.request(url: "https://archive.org/details/1"))
        let second = await submitJob(engine, Fix.request(url: "https://archive.org/details/2"))
        _ = await collector.waitForState(first) { $0 == .running }

        await engine.pause(first)
        await expectState(collector, first) { $0 == .paused }
        // The child is SIGTERMed and the freed slot goes to the waiting queued job.
        await expectState(collector, second) { $0 == .running }
        let cancelled = await pollUntil { runner.cancelledCount == 1 }
        XCTAssertTrue(cancelled)
    }

    private func pollUntil(
        _ predicate: @Sendable () -> Bool,
        timeout: TimeInterval = 2
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return predicate()
    }

    func test_resumePausedJob_reEnqueuesAtTail() async throws {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(30)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe, cap: 1)
        let collector = EventCollector(engine.events)

        let first = await submitJob(engine, Fix.request(url: "https://archive.org/details/1"))
        let second = await submitJob(engine, Fix.request(url: "https://archive.org/details/2"))
        _ = await collector.waitForState(first) { $0 == .running }

        await engine.pause(first)
        await expectState(collector, first) { $0 == .paused }
        await engine.resume(first)

        // resume() re-appends the job at the list tail with progress state cleared.
        let snapshot = await engine.currentSnapshot()
        let ids = snapshot.jobs.map(\.id)
        XCTAssertEqual(ids.last, first, "list: \(snapshot.jobs.map { ($0.id, $0.state) })")
        XCTAssertTrue(ids.contains(second))
        let resumed = try XCTUnwrap(snapshot.jobs.first { $0.id == first })
        XCTAssertEqual(resumed.state, .queued)
        XCTAssertNil(resumed.sizeBytes)
    }

    func test_resumedJobResetsSizeBytesOnFreshSpawn() async {
        let runner = FakeProcessRunner()
        runner.script(
            Fix.completingScript([Fix.progressLine(" 50.0%", total: "4242")]),
            forPathEndingIn: "yt-dlp"
        )
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe, cap: 1)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        await expectState(collector, id) { $0 == .completed }

        // The completion snapshot carries the process's reported total.
        XCTAssertEqual(collector.latestSnapshot()?.jobs.first { $0.id == id }?.sizeBytes, 4242)
    }

    func test_cancelRunningJob_keepsPartAndLog() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let part = try writePart(dir)

        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(30)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let logDeleted = LockedBox<[UUID]>([])
        let engine = try engineWithLogSink(runner: runner, probe: probe, cap: 1) { id in
            logDeleted.mutate { $0.append(id) }
        }
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request(destFolder: dir))
        _ = await collector.waitForState(id) { $0 == .running }
        await engine.cancel(id)
        await expectState(collector, id) { $0 == .cancelled }

        XCTAssertEqual(runner.cancelledCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: part.path))
        XCTAssertTrue(logDeleted.read { $0.isEmpty })
        XCTAssertNotNil(collector.latestSnapshot()?.jobs.first { $0.id == id })
    }

    func test_removeRunningJob_deletesPartAndLog_leavesList() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let part = try writePart(dir)

        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(30)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let logDeleted = LockedBox<[UUID]>([])
        let engine = try engineWithLogSink(runner: runner, probe: probe, cap: 1) { id in
            logDeleted.mutate { $0.append(id) }
        }
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request(destFolder: dir))
        _ = await collector.waitForState(id) { $0 == .running }
        await engine.remove(id)
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(runner.cancelledCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: part.path))
        XCTAssertEqual(logDeleted.read { $0 }, [id])
        XCTAssertNil(collector.latestSnapshot()?.jobs.first { $0.id == id })
    }

    func test_removeTerminalJob_leavesList() async {
        let runner = FakeProcessRunner()
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        await expectState(collector, id) { $0 == .completed }
        await engine.remove(id)
        try? await Task.sleep(for: .milliseconds(20))

        let snapshot = await engine.currentSnapshot()
        XCTAssertTrue(snapshot.jobs.isEmpty)
        XCTAssertNil(collector.latestSnapshot()?.jobs.first { $0.id == id })
    }
}
