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
}
