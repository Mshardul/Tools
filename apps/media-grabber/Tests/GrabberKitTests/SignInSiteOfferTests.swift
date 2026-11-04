@testable import GrabberKit
import XCTest

final class SignInSiteOfferTests: XCTestCase {
    func testCheckBrowserGainsTheActionOnlyWhenOffered() {
        let plain = DownloadEngine.availableActions(
            for: .failed(.ageRestricted), signInAdvice: .checkBrowser, offerSiteSignIn: false
        )
        let offered = DownloadEngine.availableActions(
            for: .failed(.ageRestricted), signInAdvice: .checkBrowser, offerSiteSignIn: true
        )
        let suggest = DownloadEngine.availableActions(
            for: .failed(.ageRestricted), signInAdvice: .suggest, offerSiteSignIn: false
        )
        XCTAssertFalse(plain.contains(.retryWithCookies))
        XCTAssertTrue(offered.contains(.retryWithCookies))
        XCTAssertTrue(suggest.contains(.retryWithCookies))
    }
}
