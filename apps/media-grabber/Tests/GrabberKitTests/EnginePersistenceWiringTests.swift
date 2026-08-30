@testable import GrabberKit
import TestSupport
import XCTest

final class EnginePersistenceWiringTests: XCTestCase {
    private typealias Fix = EngineFixture

    private func engine(
        runner: FakeProcessRunner,
        probe: FakeMetadataProbe,
        persistence: FakeQueuePersisting,
        cap: Int = 2
    ) -> DownloadEngine {
        DownloadEngine(
            dependencies: EngineDependencies(
                runner: runner,
                probe: probe,
                envProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
                ytDlpURL: Fix.ytDlp,
                jobLogDir: Fix.scratchLogDir(),
                debugFlags: EngineDebugFlags(concurrencyCapOverride: cap),
                persistence: persistence
            ),
            preferences: Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        )
    }

    private func persistedJob(
        _ index: Int,
        state: PersistedState = .queued,
        probeComplete: Bool = true,
        finishedAt: Date? = nil
    ) -> PersistedJob {
        PersistedJob(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")!,
            request: Fix.request(url: "https://archive.org/details/\(index)"),
            title: probeComplete ? "t" : nil,
            extractor: probeComplete ? "youtube" : nil,
            durationSeconds: probeComplete ? 10 : nil,
            state: state, attempt: 0, playlistGroupID: nil,
            addedAt: Date(timeIntervalSince1970: TimeInterval(index)), finishedAt: finishedAt
        )
    }

    func test_terminalTransition_callsSaveHistoryAndSaveQueue() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(30)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let persistence = FakeQueuePersisting()
        let engine = engine(runner: runner, probe: probe, persistence: persistence, cap: 1)
        let collector = EventCollector(engine.events)

        let queued = await submitJob(engine, Fix.request(url: "https://archive.org/details/1"))
        _ = await collector.waitForState(queued) { $0 == .running }
        await engine.pause(queued)
        _ = await collector.waitForState(queued) { $0 == .paused }

        runner.perRunDelay = .zero
        let done = await submitJob(engine, Fix.request(url: "https://archive.org/details/2"))
        await expectState(collector, done) { $0 == .completed }

        let history = persistence.lastHistorySave ?? []
        XCTAssertEqual(history.map(\.id), [done])
        XCTAssertEqual(history.first?.state, .completed)
        let queue = persistence.lastQueueSave ?? []
        XCTAssertTrue(queue.contains { $0.id == queued })
        XCTAssertFalse(queue.contains { $0.id == done })
    }

    func test_restoreMixedSet_listMatches_orderPreserved() async {
        let persistence = FakeQueuePersisting()
        let engine = engine(
            runner: FakeProcessRunner(),
            probe: FakeMetadataProbe(),
            persistence: persistence
        )
        let active = [persistedJob(3), persistedJob(1)]
        let history = [persistedJob(
            2,
            state: .completed,
            finishedAt: Date(timeIntervalSince1970: 5)
        )]

        await engine.restore(active: active, history: history)
        let snapshot = await engine.currentSnapshot()

        XCTAssertEqual(snapshot.jobs.map(\.id), [active[0].id, active[1].id, history[0].id])
        XCTAssertEqual(snapshot.jobs.last?.state, .completed)
    }

    func test_fullMetadataRestoredJob_noProbeSpawned_straightToDownload() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(30)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = engine(runner: runner, probe: probe, persistence: FakeQueuePersisting())
        let collector = EventCollector(engine.events)

        await engine.restore(active: [persistedJob(1, probeComplete: true)], history: [])
        _ = await collector.waitForState(persistedJob(1).id) { $0 == .running }
        let launched = await poll { runner.launches.count == 1 }

        XCTAssertTrue(launched)
        XCTAssertTrue(probe.probedURLs.isEmpty)
    }

    private func poll(_ predicate: @Sendable () -> Bool, timeout: TimeInterval = 2) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return predicate()
    }

    func test_partialMetadataRestoredJob_probeSpawned() async {
        let runner = FakeProcessRunner()
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = engine(runner: runner, probe: probe, persistence: FakeQueuePersisting())
        let collector = EventCollector(engine.events)

        await engine.restore(active: [persistedJob(1, probeComplete: false)], history: [])
        _ = await collector.waitForState(persistedJob(1).id) { $0 == .completed }

        XCTAssertEqual(probe.probedURLs.count, 1)
    }

    func test_restoredActiveJobWithFakePart_notDeletedBeforeSpawn() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-resume-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let part = dir.appendingPathComponent("t.mp4.part")
        try Data("half".utf8).write(to: part)

        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(30)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = engine(runner: runner, probe: probe, persistence: FakeQueuePersisting())
        let collector = EventCollector(engine.events)

        var job = persistedJob(1, probeComplete: true)
        job.request = Fix.request(url: "https://archive.org/details/1", destFolder: dir)
        await engine.restore(active: [job], history: [])
        _ = await collector.waitForState(job.id) { $0 == .running }

        XCTAssertTrue(FileManager.default.fileExists(atPath: part.path))
    }

    func test_restoreProducedJobs_signalsHasGrabbedOnce() async {
        let engine = engine(
            runner: FakeProcessRunner(),
            probe: FakeMetadataProbe(),
            persistence: FakeQueuePersisting()
        )
        await engine.restore(active: [], history: [])
        let none = await engine.producedJobsOnRestore
        XCTAssertFalse(none)

        await engine.restore(active: [persistedJob(1)], history: [])
        let some = await engine.producedJobsOnRestore
        XCTAssertTrue(some)
    }
}
