@testable import GrabberKit
import XCTest

final class ErrorClassKeyTests: XCTestCase {
    private let all: [ErrorClass] = [
        .rateLimited(), .botCheck, .sabrGated, .formatsMissing, .cookieReadFailed,
        .geoBlocked, .private, .unavailable, .ageRestricted, .networkDown,
        .diskFull, .permissionDenied, .incomplete, .depMissing, .potProviderDown,
        .unknown(raw: "x")
    ]

    func test_everyCaseHasADistinctKey() {
        let keys = all.map(\.key)
        XCTAssertEqual(Set(keys).count, all.count)
        XCTAssertFalse(keys.contains(where: \.isEmpty))
    }

    func test_rateLimitedKeyIsStableRegardlessOfRetryAfter() {
        XCTAssertEqual(ErrorClass.rateLimited().key, "rate_limited")
        XCTAssertEqual(ErrorClass.rateLimited(retryAfterSeconds: 90).key, "rate_limited")
    }

    func test_retryAfterSeconds() {
        XCTAssertEqual(ErrorClass.rateLimited(retryAfterSeconds: 45).retryAfterSeconds, 45)
        XCTAssertNil(ErrorClass.rateLimited().retryAfterSeconds)
        XCTAssertNil(ErrorClass.networkDown.retryAfterSeconds)
    }
}
