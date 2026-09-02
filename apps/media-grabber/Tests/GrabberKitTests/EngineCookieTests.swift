@testable import GrabberKit
import TestSupport
import XCTest

final class EngineCookieTests: XCTestCase {
    private typealias Fix = EngineFixture
    private let home = URL(fileURLWithPath: "/Users/tester")

    private var safariCookiePath: String {
        home.appendingPathComponent(
            "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
        ).path
    }

    private var chromeDir: String {
        home.appendingPathComponent("Library/Application Support/Google/Chrome").path
    }

    private func prefs(_ source: CookieSource) -> Preferences {
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.cookiesFromBrowser = source
        return prefs
    }

    private func probe() -> FakeMetadataProbe {
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        return probe
    }

    private func safariReadableFM() -> FakeFileManaging {
        var fm = FakeFileManaging()
        fm.files = [safariCookiePath]
        fm.readable = [safariCookiePath]
        return fm
    }

    // MARK: - Spawn-time resolution

    func test_safariGranted_argvCarriesCookiesFromBrowser() async {
        let runner = FakeProcessRunner()
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(
            runner: runner, probe: probe(), preferences: prefs(.safari),
            fileManager: safariReadableFM(), resolverHome: home
        )
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request())
        await expectState(collector, id) { $0 == .completed }

        let argv = runner.launches.first?.arguments ?? []
        let idx = argv.firstIndex(of: "--cookies-from-browser")
        XCTAssertNotNil(idx)
        XCTAssertEqual(idx.map { argv[$0 + 1] }, "safari")
    }

    func test_safariDenied_noCookieTokens() async {
        let runner = FakeProcessRunner()
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        var fm = FakeFileManaging()
        fm.files = [safariCookiePath]
        let engine = Fix.engine(
            runner: runner, probe: probe(), preferences: prefs(.safari),
            fileManager: fm, resolverHome: home
        )
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request())
        await expectState(collector, id) { $0 == .completed }
        XCTAssertFalse((runner.launches.first?.arguments ?? []).contains("--cookies-from-browser"))
    }

    // MARK: - The Extracted 0 cookies override

    func test_zeroCookiesLine_plusNonZeroExit_withCookieArg_classifiesCookieReadFailed() async {
        var fm = FakeFileManaging()
        fm.dirs = [chromeDir: [home.appendingPathComponent("x")]]
        let runner = FakeProcessRunner()
        runner.script(
            FakeProcessRunner.Script(
                lines: [
                    .stderr("WARNING: Extracted 0 cookies from chrome"),
                    .stderr("ERROR: Sign in to confirm you're not a bot")
                ],
                exitCode: 1
            ),
            forPathEndingIn: "yt-dlp"
        )
        let engine = Fix.engine(
            runner: runner, probe: probe(), preferences: prefs(.chrome),
            fileManager: fm, resolverHome: home
        )
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request())
        await expectState(collector, id) { state in
            if case .failed(.cookieReadFailed) = state {
                return true
            }
            return false
        }
        let job = await engine.currentSnapshot().jobs.first { $0.id == id }
        XCTAssertEqual(job?.attempt, 0)
    }

    func test_zeroCookiesLine_withoutCookieArg_usesNormalClassification() async {
        let runner = FakeProcessRunner()
        runner.script(
            FakeProcessRunner.Script(
                lines: [
                    .stderr("WARNING: Extracted 0 cookies"),
                    .stderr("ERROR: Private video")
                ],
                exitCode: 1
            ),
            forPathEndingIn: "yt-dlp"
        )
        let engine = Fix.engine(runner: runner, probe: probe())
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request())
        await expectState(collector, id) { state in
            if case .failed(.private) = state {
                return true
            }
            return false
        }
    }

    func test_zeroCookiesLine_onExitZero_completes() async {
        var fm = FakeFileManaging()
        fm.dirs = [chromeDir: [home.appendingPathComponent("x")]]
        let runner = FakeProcessRunner()
        runner.script(
            FakeProcessRunner.Script(
                lines: [
                    .stderr("WARNING: Extracted 0 cookies"),
                    .stdout("[download] 100%")
                ],
                exitCode: 0
            ),
            forPathEndingIn: "yt-dlp"
        )
        let engine = Fix.engine(
            runner: runner, probe: probe(), preferences: prefs(.chrome),
            fileManager: fm, resolverHome: home
        )
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request())
        await expectState(collector, id) { $0 == .completed }
    }
}
