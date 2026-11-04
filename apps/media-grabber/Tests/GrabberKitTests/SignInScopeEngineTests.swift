@testable import GrabberKit
import TestSupport
import XCTest

final class SignInScopeEngineTests: XCTestCase {
    private typealias Fix = EngineFixture
    private let home = URL(fileURLWithPath: "/Users/tester")

    private var safariCookiePath: String {
        home.appendingPathComponent(
            "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
        ).path
    }

    private func prefs(_ source: CookieSource, scope: SignInScope, sites: [String]) -> Preferences {
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.cookiesFromBrowser = source
        prefs.signInScope = scope
        prefs.signInSites = sites
        return prefs
    }

    private func safariReadableFM() -> FakeFileManaging {
        var fm = FakeFileManaging()
        fm.files = [safariCookiePath]
        fm.readable = [safariCookiePath]
        return fm
    }

    private func probe() -> FakeMetadataProbe {
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        return probe
    }

    private func argvHasCookies(_ runner: FakeProcessRunner) -> Bool {
        runner.launches.contains { $0.arguments.contains("--cookies-from-browser") }
    }

    private func download(_ url: String, prefs: Preferences) async -> FakeProcessRunner {
        let runner = FakeProcessRunner()
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(
            runner: runner,
            probe: probe(),
            preferences: prefs,
            fileManager: safariReadableFM(),
            resolverHome: home
        )
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request(url: url))
        await expectState(collector, id) { $0 == .completed }
        return runner
    }

    func testAllSitesSendsTheBrowserOnVimeo() async {
        let runner = await download(
            "https://vimeo.com/1",
            prefs: prefs(.safari, scope: .allSites, sites: ["youtube"])
        )
        XCTAssertTrue(argvHasCookies(runner))
    }

    func testListedSitesSendsTheBrowserOnlyForAListedHost() async {
        let youtube = await download(
            "https://youtube.com/watch?v=a",
            prefs: prefs(.safari, scope: .listedSites, sites: ["youtube"])
        )
        let vimeo = await download(
            "https://vimeo.com/1",
            prefs: prefs(.safari, scope: .listedSites, sites: ["youtube"])
        )
        XCTAssertTrue(argvHasCookies(youtube))
        XCTAssertFalse(argvHasCookies(vimeo))
    }

    func testEmptyListedSitesSendsNoBrowser() async {
        let runner = await download(
            "https://youtube.com/watch?v=a",
            prefs: prefs(.safari, scope: .listedSites, sites: [])
        )
        XCTAssertFalse(argvHasCookies(runner))
    }

    func testNoBrowserSendsNothing() async {
        let runner = await download(
            "https://youtube.com/watch?v=a",
            prefs: prefs(.none, scope: .allSites, sites: [])
        )
        XCTAssertFalse(argvHasCookies(runner))
    }

    func testUnlistedHostSuggestsSignIn() async {
        let runner = FakeProcessRunner()
        runner.script(
            FakeProcessRunner.Script.stderr("ERROR: Sign in to confirm your age", exitCode: 1),
            forPathEndingIn: "yt-dlp"
        )
        let engine = Fix.engine(
            runner: runner,
            probe: probe(),
            preferences: prefs(.safari, scope: .listedSites, sites: []),
            fileManager: safariReadableFM(),
            resolverHome: home
        )
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request(url: "https://vimeo.com/1"))
        await expectState(collector, id) {
            if case .failed = $0 {
                true
            } else {
                false
            }
        }
        let snapshot = await engine.currentSnapshot()
        XCTAssertEqual(snapshot.jobs.first?.signInAdvice, .suggest)
        XCTAssertTrue(snapshot.jobs.first?.availableActions.contains(.retryWithCookies) == true)
        XCTAssertFalse(argvHasCookies(runner))
    }
}
