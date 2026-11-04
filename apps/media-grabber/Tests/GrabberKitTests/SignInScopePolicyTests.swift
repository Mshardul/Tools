@testable import GrabberKit
import XCTest

final class SignInScopePolicyTests: XCTestCase {
    func testAllSitesIgnoresTheList() {
        XCTAssertTrue(SignInScopePolicy.sendsCookies(scope: .allSites, sites: [], host: "youtube"))
        XCTAssertTrue(SignInScopePolicy.sendsCookies(scope: .allSites, sites: [], host: "vimeo"))
        XCTAssertTrue(SignInScopePolicy.sendsCookies(scope: .allSites, sites: ["youtube"], host: "vimeo"))
    }

    func testListedSitesSendsCookiesOnlyForNamedHosts() {
        XCTAssertTrue(SignInScopePolicy.sendsCookies(scope: .listedSites, sites: ["youtube"], host: "youtube"))
        XCTAssertFalse(SignInScopePolicy.sendsCookies(scope: .listedSites, sites: ["youtube"], host: "vimeo"))
        XCTAssertFalse(SignInScopePolicy.sendsCookies(scope: .listedSites, sites: [], host: "youtube"))
    }

    func testFreshPreferencesAreAllSites() throws {
        let prefs = try Preferences(defaults: XCTUnwrap(UserDefaults(suiteName: UUID().uuidString)))
        XCTAssertEqual(prefs.signInScope, .allSites)
        XCTAssertEqual(prefs.signInSites, [])
        prefs.signInScope = .listedSites
        prefs.signInSites = ["youtube"]
        prefs.resetToDefaults()
        XCTAssertEqual(prefs.signInScope, .allSites)
        XCTAssertEqual(prefs.signInSites, [])
    }
}
