@testable import GrabberKit
import TestSupport
import XCTest

final class EnginePasscodeTests: XCTestCase {
    private typealias Fix = EngineFixture
    private let url = "https://example.zoom.us/rec/share/abc"
    private let requiredLine = "ERROR: [zoom] abc: This video is protected by a passcode, "
        + "use the --video-password option"
    private let geoLine = "ERROR: The uploader has not made this video available in your country"

    private func probe() -> FakeMetadataProbe {
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        return probe
    }

    private func request() -> DownloadRequest {
        Fix.request(url: url)
    }

    private func waitForLaunches(_ runner: FakeProcessRunner, _ count: Int) async {
        for _ in 0 ..< 200 where runner.launches.count < count {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func passcodeArguments(_ launch: ProcessLaunch?) -> [String] {
        (launch?.arguments ?? []).filter { $0.hasPrefix("--video-password") }
    }

    private struct FailedJob {
        let engine: DownloadEngine
        let id: UUID
        let runner: FakeProcessRunner
    }

    private func failedJob(line: String) async -> FailedJob {
        let runner = FakeProcessRunner()
        runner.script(.stderr(line, exitCode: 1), forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(runner: runner, probe: probe())
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, request())
        await expectState(collector, id) { state in
            if case .failed = state {
                return true
            }
            return false
        }
        return FailedJob(engine: engine, id: id, runner: runner)
    }

    private func storedPasscode(_ engine: DownloadEngine) async -> String? {
        await engine.makeContext(url: url, attempt: 0).videoPassword
    }

    private func jobPasscode(_ engine: DownloadEngine, _ id: UUID) async -> String? {
        await engine.jobs.first { $0.id == id }?.videoPassword
    }

    func test_removingAnotherJobForTheSameLinkDoesNotWipeAPendingPasscode() async {
        let runner = FakeProcessRunner()
        runner.script(.stderr(geoLine, exitCode: 1), forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(runner: runner, probe: probe())
        let collector = EventCollector(engine.events)
        let stale = await submitJob(engine, request())
        await expectState(collector, stale) { state in
            if case .failed = state {
                return true
            }
            return false
        }
        await engine.setPasscode("p", for: url)
        await engine.remove(stale)
        _ = await submitJob(engine, request())
        await waitForLaunches(runner, 2)
        XCTAssertEqual(runner.launches.count, 2)
        XCTAssertEqual(passcodeArguments(runner.launches.last), ["--video-password=p"])
    }

    func test_probeUsesPasscode() async {
        let probe = probe()
        let engine = Fix.engine(runner: FakeProcessRunner(), probe: probe)
        await engine.setPasscode("p", for: url)
        _ = await engine.preview(url)
        XCTAssertEqual(probe.probedContexts.last?.videoPassword, "p")
    }

    func test_downloadArgvCarriesPasscode() async {
        let runner = FakeProcessRunner()
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(runner: runner, probe: probe())
        await engine.setPasscode("p", for: url)
        _ = await submitJob(engine, request())
        await waitForLaunches(runner, 1)
        XCTAssertEqual(passcodeArguments(runner.launches.first), ["--video-password=p"])
    }

    func test_jobLogNeverContainsPasscode() async throws {
        let logDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mg-pc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: logDir) }
        let runner = FakeProcessRunner()
        runner.script(Fix.completingScript([.stdout("[zoom] abc: Validating passcode")]), forPathEndingIn: "yt-dlp")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let engine = DownloadEngine(
            dependencies: EngineDependencies(
                runner: runner,
                probe: probe(),
                envProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
                ytDlpURL: Fix.ytDlp,
                jobLogDir: logDir,
                debugFlags: EngineDebugFlags(concurrencyCapOverride: 1)
            ),
            preferences: Preferences(defaults: defaults)
        )
        let collector = EventCollector(engine.events)
        await engine.setPasscode("hunter two", for: url)
        let id = await submitJob(engine, request())
        await expectState(collector, id) { $0 == .completed }
        let file = logDir.appendingPathComponent("\(id.uuidString).log")
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains("Validating passcode"))
        XCTAssertFalse(text.contains("hunter"))
    }

    func test_failedPasscodeJob_retryWithPasscodeRequeuesWithTheFlag() async {
        let failed = await failedJob(line: requiredLine)
        XCTAssertEqual(failed.runner.launches.count, 1)
        XCTAssertTrue(passcodeArguments(failed.runner.launches.first).isEmpty)
        await failed.engine.retryWithPasscode(failed.id, passcode: "p")
        await waitForLaunches(failed.runner, 2)
        XCTAssertEqual(failed.runner.launches.count, 2)
        XCTAssertEqual(passcodeArguments(failed.runner.launches.last), ["--video-password=p"])
    }

    func test_retryWithPasscode_onNonPasscodeFailureIsNoOp() async {
        let failed = await failedJob(line: geoLine)
        await failed.engine.retryWithPasscode(failed.id, passcode: "p")
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(failed.runner.launches.count, 1)
        let stored = await storedPasscode(failed.engine)
        XCTAssertNil(stored)
    }

    func test_retryWithPasscode_onCompletedJobIsNoOp() async {
        let runner = FakeProcessRunner()
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(runner: runner, probe: probe())
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, request())
        await expectState(collector, id) { $0 == .completed }
        await engine.retryWithPasscode(id, passcode: "p")
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(runner.launches.count, 1)
        let stored = await storedPasscode(engine)
        XCTAssertNil(stored)
    }

    func test_completedJobDropsPasscode() async {
        let runner = FakeProcessRunner()
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(runner: runner, probe: probe())
        let collector = EventCollector(engine.events)
        await engine.setPasscode("p", for: url)
        let id = await submitJob(engine, request())
        await expectState(collector, id) { $0 == .completed }
        let stored = await jobPasscode(engine, id)
        XCTAssertNil(stored)
    }

    func test_submittedJobTakesThePasscodeOutOfThePendingList() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(30)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(runner: runner, probe: probe(), cap: 1)
        await engine.setPasscode("p", for: url)
        let id = await submitJob(engine, request())
        let pending = await storedPasscode(engine)
        let owned = await jobPasscode(engine, id)
        XCTAssertNil(pending)
        XCTAssertEqual(owned, "p")
    }

    func test_failedJobDropsPasscode() async {
        let runner = FakeProcessRunner()
        runner.script(.stderr(geoLine, exitCode: 1), forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(runner: runner, probe: probe())
        let collector = EventCollector(engine.events)
        await engine.setPasscode("p", for: url)
        let id = await submitJob(engine, request())
        await expectState(collector, id) { state in
            if case .failed = state {
                return true
            }
            return false
        }
        let stored = await jobPasscode(engine, id)
        XCTAssertNil(stored)
    }

    func test_probeFailureDropsPasscode() async {
        let probe = FakeMetadataProbe(default: .failure(.passcodeRejected))
        let engine = Fix.engine(runner: FakeProcessRunner(), probe: probe)
        let collector = EventCollector(engine.events)
        await engine.setPasscode("p", for: url)
        let id = await submitJob(engine, request())
        await expectState(collector, id) { state in
            if case .failed = state {
                return true
            }
            return false
        }
        let stored = await jobPasscode(engine, id)
        XCTAssertNil(stored)
    }

    func test_cancelledJobDropsPasscode() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(30)
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(runner: runner, probe: probe(), cap: 1)
        let collector = EventCollector(engine.events)
        await engine.setPasscode("p", for: url)
        let id = await submitJob(engine, request())
        _ = await collector.waitForState(id) { $0 == .running }
        await engine.cancel(id)
        await expectState(collector, id) { $0 == .cancelled }
        let afterCancel = await jobPasscode(engine, id)
        XCTAssertNil(afterCancel)
    }

    func test_restartAfterFailureDoesNotReusePasscode() async {
        let runner = FakeProcessRunner()
        runner.script(.stderr("ERROR: Failed to decrypt with DPAPI", exitCode: 1), forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(runner: runner, probe: probe())
        let collector = EventCollector(engine.events)
        await engine.setPasscode("p", for: url)
        let id = await submitJob(engine, request())
        await expectState(collector, id) { state in
            if case .failed = state {
                return true
            }
            return false
        }
        XCTAssertEqual(passcodeArguments(runner.launches.first), ["--video-password=p"])
        await engine.retry(id)
        await waitForLaunches(runner, 2)
        XCTAssertEqual(runner.launches.count, 2)
        XCTAssertTrue(passcodeArguments(runner.launches.last).isEmpty)
    }

    func test_automaticRetryKeepsPasscode() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let runner = FakeProcessRunner()
        runner.script(.stderr("ERROR: HTTP Error 429: Too Many Requests", exitCode: 1), forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(runner: runner, probe: probe(), clock: clock, maxAutoRetries: 3)
        await engine.setPasscode("p", for: url)
        let id = await submitJob(engine, request())
        await waitForLaunches(runner, 1)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let stored = await jobPasscode(engine, id)
        XCTAssertEqual(stored, "p")
    }
}
