@testable import GrabberKit
import TestSupport
import XCTest

final class CookieResolverResolveTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/tester")

    private var safariCookiePath: String {
        home.appendingPathComponent(
            "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
        ).path
    }

    private var chromeDir: String {
        home.appendingPathComponent("Library/Application Support/Google/Chrome").path
    }

    private func resolver(_ fm: FakeFileManaging) -> CookieResolver {
        CookieResolver(fileManager: fm, home: home)
    }

    private func firefoxFM(ini: String) -> FakeFileManaging {
        var fm = FakeFileManaging()
        let iniPath = home
            .appendingPathComponent("Library/Application Support/Firefox/profiles.ini").path
        fm.files = [iniPath]
        fm.readable = [iniPath]
        fm.contents = [iniPath: ini]
        return fm
    }

    func test_none_noOverride_unconfigured() {
        let got = resolver(FakeFileManaging()).resolve(source: .none, jobOverride: false)
        XCTAssertNil(got.argument)
        XCTAssertEqual(got.verdict, .unconfigured)
    }

    func test_none_override_picksSafariWhenReadable() {
        var fm = FakeFileManaging()
        fm.files = [safariCookiePath]
        fm.readable = [safariCookiePath]
        let got = resolver(fm).resolve(source: .none, jobOverride: true)
        XCTAssertEqual(got.argument, "safari")
        XCTAssertEqual(got.verdict, .ready(browserKey: "safari"))
    }

    func test_none_override_fallsToFirstExistingBrowserDir() {
        var fm = FakeFileManaging()
        fm.dirs = [chromeDir: [home.appendingPathComponent("x")]]
        let got = resolver(fm).resolve(source: .none, jobOverride: true)
        XCTAssertEqual(got.argument, "chrome")
        XCTAssertEqual(got.verdict, .ready(browserKey: "chrome"))
    }

    func test_none_override_noBrowsers_unconfigured() {
        let got = resolver(FakeFileManaging()).resolve(source: .none, jobOverride: true)
        XCTAssertNil(got.argument)
        XCTAssertEqual(got.verdict, .unconfigured)
    }

    func test_safari_denied_needsFullDiskAccess() {
        var fm = FakeFileManaging()
        fm.files = [safariCookiePath]
        let got = resolver(fm).resolve(source: .safari, jobOverride: false)
        XCTAssertNil(got.argument)
        XCTAssertEqual(got.verdict, .needsFullDiskAccess)
    }

    func test_safari_granted_ready() {
        var fm = FakeFileManaging()
        fm.files = [safariCookiePath]
        fm.readable = [safariCookiePath]
        let got = resolver(fm).resolve(source: .safari, jobOverride: false)
        XCTAssertEqual(got.argument, "safari")
        XCTAssertEqual(got.verdict, .ready(browserKey: "safari"))
    }

    func test_chrome_ready() {
        let got = resolver(FakeFileManaging()).resolve(source: .chrome, jobOverride: false)
        XCTAssertEqual(got.argument, "chrome")
        XCTAssertEqual(got.verdict, .ready(browserKey: "chrome"))
    }

    func test_firefox_namedProfilePresent() {
        let fm = firefoxFM(ini: """
        [Profile0]
        Name=work
        Path=Profiles/work
        """)
        let got = resolver(fm).resolve(source: .firefox(profile: "work"), jobOverride: false)
        XCTAssertEqual(got.argument, "firefox:work")
        XCTAssertEqual(got.verdict, .ready(browserKey: "firefox"))
    }

    func test_firefox_namedProfileAbsent_fallsToDefault() {
        let fm = firefoxFM(ini: """
        [Profile0]
        Name=main
        Path=Profiles/main
        Default=1
        """)
        let got = resolver(fm).resolve(source: .firefox(profile: "gone"), jobOverride: false)
        XCTAssertEqual(got.argument, "firefox:main")
    }

    func test_firefox_noProfiles_noProfilesVerdict() {
        let fm = firefoxFM(ini: "[General]\nStartWithLastProfile=1")
        let got = resolver(fm).resolve(source: .firefox(profile: nil), jobOverride: false)
        XCTAssertNil(got.argument)
        XCTAssertEqual(got.verdict, .noProfiles)
    }
}
