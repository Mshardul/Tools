@testable import GrabberKit
import TestSupport
import XCTest

final class EngineJobLogTests: XCTestCase {
    private typealias Fix = EngineFixture

    private func makeEngine(
        runner: FakeProcessRunner,
        probe: FakeMetadataProbe,
        logDir: URL,
        cap: Int = 2
    ) -> DownloadEngine {
        DownloadEngine(
            dependencies: EngineDependencies(
                runner: runner,
                probe: probe,
                envProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
                ytDlpURL: Fix.ytDlp,
                jobLogDir: logDir,
                debugFlags: EngineDebugFlags(concurrencyCapOverride: cap)
            ),
            preferences: Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        )
    }

    func test_run_writesHeaderAndStreamedLines() async throws {
        let logDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-ejl-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: logDir) }

        let runner = FakeProcessRunner()
        runner.perLineDelay = .milliseconds(5)
        runner.script(
            FakeProcessRunner.Script(
                lines: [.stdout("MG| 50.0%|1.00MiB/s|00:10|100|1000"), .stderr("a note")],
                exitCode: 0
            ),
            forPathEndingIn: "yt-dlp"
        )
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = makeEngine(runner: runner, probe: probe, logDir: logDir)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        await expectState(collector, id) { $0 == .completed }

        let file = logDir.appendingPathComponent("\(id.uuidString).log")
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains("----"))
        XCTAssertTrue(text.contains("[stderr] a note"))
    }

    func test_remove_deletesLogFile() async {
        let logDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-ejl-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: logDir) }

        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(30)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = makeEngine(runner: runner, probe: probe, logDir: logDir, cap: 1)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        _ = await collector.waitForState(id) { $0 == .running }
        try? await Task.sleep(for: .milliseconds(20))
        let file = logDir.appendingPathComponent("\(id.uuidString).log")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        await engine.remove(id)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func test_terminalCap_dropsOldestJobAndItsLog() async throws {
        let logDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-ejl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: logDir) }

        let runner = FakeProcessRunner()
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = makeEngine(runner: runner, probe: probe, logDir: logDir, cap: 6)
        let collector = EventCollector(engine.events)

        var ids: [UUID] = []
        for index in 0 ..< 201 {
            let id = await submitJob(
                engine,
                Fix.request(url: "https://archive.org/details/\(index)")
            )
            ids.append(id)
            _ = await collector.waitForState(id) { $0 == .completed }
        }

        let snapshot = await engine.currentSnapshot()
        XCTAssertEqual(snapshot.jobs.count, 200)
        XCTAssertNil(snapshot.jobs.first { $0.id == ids[0] })
        let droppedLog = logDir.appendingPathComponent("\(ids[0].uuidString).log")
        XCTAssertFalse(FileManager.default.fileExists(atPath: droppedLog.path))
    }
}
