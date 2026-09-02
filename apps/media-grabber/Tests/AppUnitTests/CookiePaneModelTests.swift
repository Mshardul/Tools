@testable import GrabberKit
@testable import MediaGrabber
import TestSupport
import XCTest

@MainActor
final class CookiePaneModelTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/tester")

    private func prefs(_ source: CookieSource) -> Preferences {
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.cookiesFromBrowser = source
        return prefs
    }

    private func resolver(
        profiles: [FirefoxProfile],
        safari: SafariCookieAccess
    ) -> CookieResolver {
        var fm = FakeFileManaging()
        if !profiles.isEmpty {
            let iniPath = home
                .appendingPathComponent("Library/Application Support/Firefox/profiles.ini").path
            fm.files.insert(iniPath)
            fm.readable.insert(iniPath)
            fm.contents[iniPath] = profiles.enumerated().map { index, profile in
                let defaultLine = profile.isDefault ? "\nDefault=1" : ""
                return "[Profile\(index)]\nName=\(profile.name)\nIsRelative=0"
                    + "\nPath=\(profile.path)\(defaultLine)"
            }.joined(separator: "\n\n")
        }
        let cookiePath = home.appendingPathComponent(
            "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
        ).path
        switch safari {
        case .granted:
            fm.files.insert(cookiePath)
            fm.readable.insert(cookiePath)
        case .denied:
            fm.files.insert(cookiePath)
        case .noContainer:
            break
        }
        return CookieResolver(fileManager: fm, home: home)
    }

    func test_refresh_populatesProfilesAndSafariAccess() {
        let model = CookiePaneModel(
            prefs: prefs(.firefox(profile: "a")),
            resolver: resolver(
                profiles: [
                    FirefoxProfile(name: "a", path: "/p/a", isDefault: true),
                    FirefoxProfile(name: "b", path: "/p/b", isDefault: false)
                ],
                safari: .denied
            )
        )
        model.onAppear()
        XCTAssertEqual(model.firefoxProfiles.count, 2)
        XCTAssertEqual(model.safariAccess, .denied)
        XCTAssertTrue(model.showsFirefoxProfilePicker)
    }

    func test_refresh_rewritesStaleFirefoxProfile() {
        let model = CookiePaneModel(
            prefs: prefs(.firefox(profile: "stale")),
            resolver: resolver(
                profiles: [FirefoxProfile(name: "real", path: "/p/real", isDefault: true)],
                safari: .noContainer
            )
        )
        model.onAppear()
        XCTAssertEqual(model.source, .firefox(profile: nil))
    }

    func test_fdaRow_visibleOnlyForSafariWithContainer() {
        let denied = CookiePaneModel(
            prefs: prefs(.safari),
            resolver: resolver(profiles: [], safari: .denied)
        )
        denied.onAppear()
        XCTAssertTrue(denied.showsFullDiskAccessRow)

        let noContainer = CookiePaneModel(
            prefs: prefs(.safari),
            resolver: resolver(profiles: [], safari: .noContainer)
        )
        noContainer.onAppear()
        XCTAssertFalse(noContainer.showsFullDiskAccessRow)
    }

    func test_openFullDiskAccessSettings_callsSink() {
        let link = FakeSettingsLink()
        let model = CookiePaneModel(
            prefs: prefs(.safari),
            resolver: resolver(profiles: [], safari: .denied),
            settingsLink: link
        )
        model.openFullDiskAccessSettings()
        XCTAssertEqual(link.opened.first?.scheme, "x-apple.systempreferences")
    }

    func test_openHelp_callsOpenURLSinkWithBrowserKeyURL() {
        let sink = FakeOpenURLSink()
        let model = CookiePaneModel(
            prefs: prefs(.chrome),
            resolver: resolver(profiles: [], safari: .noContainer),
            openURL: sink
        )
        model.openHelp()
        XCTAssertEqual(sink.opened.first, CookieHelpURL.url(forBrowserKey: "chrome"))
    }

    func test_learnMoreAndTip_hiddenForNone_shownForBrowser() {
        let none = CookiePaneModel(
            prefs: prefs(.none),
            resolver: resolver(profiles: [], safari: .noContainer)
        )
        XCTAssertFalse(none.showsLearnMore)
        XCTAssertFalse(none.showsTip)

        let chrome = CookiePaneModel(
            prefs: prefs(.chrome),
            resolver: resolver(profiles: [], safari: .noContainer)
        )
        XCTAssertTrue(chrome.showsLearnMore)
        XCTAssertTrue(chrome.showsTip)
    }
}

@MainActor
final class FakeSettingsLink: SettingsLinkOpening {
    private(set) var opened: [URL] = []
    nonisolated init() {}
    func open(_ url: URL) {
        opened.append(url)
    }
}
