@testable import GrabberKit
import TestSupport
import XCTest

final class CookieResolverBrowserMatrixTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/tester")

    private func supportDir(_ relative: String) -> String {
        home.appendingPathComponent("Library/Application Support/\(relative)").path
    }

    private func resolve(_ source: CookieSource, installedDir: String?) -> CookieResolution {
        var fm = FakeFileManaging()
        if let installedDir {
            fm.files = [supportDir(installedDir)]
        }
        return CookieResolver(fileManager: fm, home: home).resolve(source: source, jobOverride: false)
    }

    private struct Chromium {
        let source: CookieSource
        let dir: String
        let key: String
    }

    private let chromium = [
        Chromium(source: .chrome, dir: "Google/Chrome", key: "chrome"),
        Chromium(source: .brave, dir: "BraveSoftware/Brave-Browser", key: "brave"),
        Chromium(source: .edge, dir: "Microsoft Edge", key: "edge")
    ]

    func test_chromiumBrowsers_installed_areReadyWithTheirOwnArgument() {
        for browser in chromium {
            let got = resolve(browser.source, installedDir: browser.dir)
            XCTAssertEqual(got.argument, browser.key, browser.key)
            XCTAssertEqual(got.verdict, .ready(browserKey: browser.key), browser.key)
        }
    }

    func test_chromiumBrowsers_missing_reportNoProfilesAndPassNoArgument() {
        for browser in chromium {
            let got = resolve(browser.source, installedDir: nil)
            XCTAssertNil(got.argument, browser.key)
            XCTAssertEqual(got.verdict, .noProfiles, browser.key)
        }
    }

    func test_chromiumBrowser_installedElsewhere_doesNotCountAsInstalled() {
        let got = resolve(.brave, installedDir: "Google/Chrome")
        XCTAssertEqual(got.verdict, .noProfiles)
    }

    func test_safari_noContainer_needsFullDiskAccess() {
        let got = resolve(.safari, installedDir: nil)
        XCTAssertNil(got.argument)
        XCTAssertEqual(got.verdict, .needsFullDiskAccess)
    }

    func test_safari_readable_isReady() {
        var fm = FakeFileManaging()
        let path = home.appendingPathComponent(
            "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
        ).path
        fm.files = [path]
        fm.readable = [path]
        let got = CookieResolver(fileManager: fm, home: home).resolve(source: .safari, jobOverride: false)
        XCTAssertEqual(got.argument, "safari")
        XCTAssertEqual(got.verdict, .ready(browserKey: "safari"))
    }

    func test_firefox_noProfilesFile_reportsNoProfiles() {
        let got = resolve(.firefox(profile: nil), installedDir: nil)
        XCTAssertNil(got.argument)
        XCTAssertEqual(got.verdict, .noProfiles)
    }

    func test_none_neverProducesAnArgument() {
        XCTAssertNil(resolve(.none, installedDir: "Google/Chrome").argument)
    }
}
