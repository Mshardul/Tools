@testable import GrabberKit
@testable import MediaGrabber
import XCTest

final class PreferencesPaneTests: XCTestCase {
    func test_railGroupsCoverEveryPaneOnce() {
        let all = PreferencesRailGroup.allCases.flatMap(\.panes)
        XCTAssertEqual(Set(all), Set(PreferencesPane.allCases))
        XCTAssertEqual(all.count, PreferencesPane.allCases.count)
    }

    func test_railOrder() {
        XCTAssertEqual(PreferencesRailGroup.general.panes, [.downloads, .appearance, .network])
        XCTAssertEqual(PreferencesRailGroup.youtube.panes, [.cookies])
        XCTAssertEqual(PreferencesRailGroup.system.panes, [.updates, .logsPrivacy, .advanced])
    }

    func test_pageDeepLinkDefault() {
        XCTAssertEqual(AppModel.Page.preferences(), .preferences(.downloads))
    }

    func test_titles() {
        XCTAssertEqual(PreferencesPane.cookies.title, "Sign-in & cookies")
        XCTAssertEqual(PreferencesPane.logsPrivacy.title, "Logs & privacy")
    }

    func test_cookieSourceDisplayNames() {
        XCTAssertEqual(SignInCookiesPane.displayName(for: .none), "None")
        XCTAssertEqual(SignInCookiesPane.displayName(for: .safari), "Safari")
        XCTAssertEqual(SignInCookiesPane.displayName(for: .edge), "Microsoft Edge")
        XCTAssertEqual(SignInCookiesPane.displayName(for: .firefox(profile: nil)), "Firefox")
    }

    func test_pendingBannerText() {
        XCTAssertEqual(
            SignInCookiesPane.pendingBannerText(jobTitle: "My Clip"),
            "Pick a browser to retry \"My Clip\" with your sign-in."
        )
        XCTAssertEqual(
            SignInCookiesPane.pendingBannerText(jobTitle: nil),
            "Pick a browser to retry \"this download\" with your sign-in."
        )
    }
}
