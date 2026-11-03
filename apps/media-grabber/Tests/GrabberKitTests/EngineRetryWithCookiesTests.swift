@testable import GrabberKit
import TestSupport
import XCTest

final class EngineRetryWithCookiesTests: XCTestCase {
    private typealias Fix = EngineFixture
    private let home = URL(fileURLWithPath: "/Users/tester")

    private func probe() -> FakeMetadataProbe {
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        return probe
    }

    private struct FailedJob {
        let engine: DownloadEngine
        let id: UUID
        let runner: FakeProcessRunner
        let collector: EventCollector
    }

    private func failedEngine(
        script: FakeProcessRunner.Script,
        fileManager: FileManaging = FoundationFileManager(),
        resolverHome: URL? = nil
    ) async -> FailedJob {
        let runner = FakeProcessRunner()
        runner.script(script, forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(
            runner: runner, probe: probe(),
            fileManager: fileManager, resolverHome: resolverHome
        )
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request())
        await expectState(collector, id) { state in
            if case .failed = state {
                return true
            }
            return false
        }
        return FailedJob(engine: engine, id: id, runner: runner, collector: collector)
    }

    func test_ageRestricted_job_restartsFromScratch_attemptZero() async {
        let fixture = await failedEngine(
            script: FakeProcessRunner.Script(lines: [.stderr("ERROR: Sign in to confirm your age")], exitCode: 1)
        )
        await fixture.engine.retryWithCookies(fixture.id)
        for _ in 0 ..< 100 where fixture.runner.launches.count < 2 {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertGreaterThanOrEqual(fixture.runner.launches.count, 2)
        let job = await fixture.engine.currentSnapshot().jobs.first { $0.id == fixture.id }
        XCTAssertEqual(job?.attempt, 0)
    }

    func test_cookieReadFailed_job_isNoOp() async {
        let fixture = await failedEngine(
            script: FakeProcessRunner.Script(
                lines: [.stderr("ERROR: could not find chrome cookies database")],
                exitCode: 1
            )
        )
        await fixture.engine.retryWithCookies(fixture.id)
        let job = await fixture.engine.currentSnapshot().jobs.first { $0.id == fixture.id }
        XCTAssertEqual(job?.state, .failed(.cookieReadFailed))
        XCTAssertEqual(fixture.runner.launches.count, 1)
    }

    func test_geoBlocked_job_isNoOp() async {
        let fixture = await failedEngine(
            script: FakeProcessRunner.Script(
                lines: [.stderr("ERROR: This video is not available in your country")],
                exitCode: 1
            )
        )
        let before = await fixture.engine.currentSnapshot().jobs
            .first { $0.id == fixture.id }?.state
        await fixture.engine.retryWithCookies(fixture.id)
        let after = await fixture.engine.currentSnapshot().jobs
            .first { $0.id == fixture.id }?.state
        XCTAssertEqual(before, after)
    }

    func test_completedJob_isNoOp() async {
        let runner = FakeProcessRunner()
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(runner: runner, probe: probe())
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request())
        await expectState(collector, id) { $0 == .completed }
        await engine.retryWithCookies(id)
        let job = await engine.currentSnapshot().jobs.first { $0.id == id }
        XCTAssertEqual(job?.state, .completed)
    }

    func test_restartAfterSignIn_carriesTheChosenBrowser() async throws {
        var fm = FakeFileManaging()
        let cookiePath = home.appendingPathComponent(
            "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
        ).path
        fm.files = [cookiePath]
        fm.readable = [cookiePath]
        let prefs = try Preferences(defaults: XCTUnwrap(UserDefaults(suiteName: UUID().uuidString)))
        let runner = FakeProcessRunner()
        runner.script(
            FakeProcessRunner.Script(lines: [.stderr("ERROR: Sign in to confirm your age")], exitCode: 1),
            forPathEndingIn: "yt-dlp"
        )
        let engine = Fix.engine(
            runner: runner, probe: probe(), preferences: prefs, fileManager: fm, resolverHome: home
        )
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request())
        await expectState(collector, id) { $0 == .failed(.ageRestricted) }
        XCTAssertFalse((runner.launches.last?.arguments ?? []).contains("--cookies-from-browser"))

        prefs.cookiesFromBrowser = .safari
        await engine.retryWithCookies(id)
        await expectState(collector, id) { $0 == .failed(.ageRestricted) }
        XCTAssertGreaterThanOrEqual(runner.launches.count, 2)
        XCTAssertTrue((runner.launches.last?.arguments ?? []).contains("--cookies-from-browser"))
    }
}
