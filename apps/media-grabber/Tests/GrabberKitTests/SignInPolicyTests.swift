@testable import GrabberKit
import XCTest

final class SignInPolicyTests: XCTestCase {
    private let youtube = RateHost(urlString: "https://www.youtube.com/watch?v=x")
    private let vimeo = RateHost(urlString: "https://vimeo.com/1")

    private let fixableEverywhere: [ErrorClass] = [.ageRestricted, .private]

    private let neverFixable: [ErrorClass] = [
        .formatsMissing, .rateLimited(), .geoBlocked, .unavailable, .networkDown, .diskFull,
        .permissionDenied, .incomplete, .depMissing, .sabrGated, .potProviderDown,
        .cookieReadFailed, .unknown(raw: "x")
    ]

    func test_ageRestrictedAndPrivate_suggestOnAnyHost() {
        for errorClass in fixableEverywhere {
            for host in [youtube, vimeo] {
                XCTAssertEqual(
                    SignInPolicy.advice(for: errorClass, host: host, cookiesConfigured: false), .suggest
                )
                XCTAssertEqual(
                    SignInPolicy.advice(for: errorClass, host: host, cookiesConfigured: true), .checkBrowser
                )
            }
        }
    }

    func test_botCheck_onlyOnYouTube() {
        XCTAssertEqual(SignInPolicy.advice(for: .botCheck, host: youtube, cookiesConfigured: false), .suggest)
        XCTAssertEqual(SignInPolicy.advice(for: .botCheck, host: youtube, cookiesConfigured: true), .checkBrowser)
        XCTAssertEqual(SignInPolicy.advice(for: .botCheck, host: vimeo, cookiesConfigured: false), .none)
        XCTAssertEqual(SignInPolicy.advice(for: .botCheck, host: vimeo, cookiesConfigured: true), .none)
    }

    func test_otherClasses_neverAdvise() {
        for errorClass in neverFixable {
            for host in [youtube, vimeo] {
                for configured in [false, true] {
                    XCTAssertEqual(
                        SignInPolicy.advice(for: errorClass, host: host, cookiesConfigured: configured), .none,
                        "\(errorClass)"
                    )
                }
            }
        }
    }

    func test_everyErrorClassIsClassified() {
        let listed = fixableEverywhere + neverFixable + [.botCheck]
        XCTAssertEqual(listed.count, 16)
    }
}
