@testable import GrabberKit
import XCTest

final class FailurePresentationTests: XCTestCase {
    private let cases: [ErrorClass] = [
        .rateLimited(), .geoBlocked, .private, .unavailable, .ageRestricted,
        .networkDown, .cookieReadFailed, .diskFull, .permissionDenied,
        .incomplete, .depMissing, .unknown(raw: "ERROR: boom")
    ]

    func test_everyCaseHasANonEmptySentence() {
        for errorClass in cases {
            XCTAssertFalse(errorClass.presentation.sentence.isEmpty, "\(errorClass)")
        }
    }

    func test_unknownSentenceIsTheRawText() {
        XCTAssertEqual(ErrorClass.unknown(raw: "ERROR: boom").presentation.sentence, "ERROR: boom")
    }

    func test_offeredActionsMatchSpec() {
        XCTAssertEqual(ErrorClass.rateLimited().presentation.offeredActions, [.retry])
        XCTAssertEqual(ErrorClass.geoBlocked.presentation.offeredActions, [])
        XCTAssertEqual(ErrorClass.private.presentation.offeredActions, [])
        XCTAssertEqual(ErrorClass.unavailable.presentation.offeredActions, [])
        XCTAssertEqual(ErrorClass.ageRestricted.presentation.offeredActions, [])
        XCTAssertEqual(ErrorClass.depMissing.presentation.offeredActions, [])
        XCTAssertEqual(ErrorClass.networkDown.presentation.offeredActions, [.retry])
        XCTAssertEqual(ErrorClass.cookieReadFailed.presentation.offeredActions, [.retry])
        XCTAssertEqual(ErrorClass.diskFull.presentation.offeredActions, [.retry])
        XCTAssertEqual(ErrorClass.permissionDenied.presentation.offeredActions, [.retry])
        XCTAssertEqual(ErrorClass.incomplete.presentation.offeredActions, [.retry])
        XCTAssertEqual(ErrorClass.unknown(raw: "x").presentation.offeredActions, [.retry])
    }

    func test_isAutoRetryableIsASubsetOfClassesOfferingRetry() {
        let retryable = cases.filter(\.isAutoRetryable)
        XCTAssertEqual(
            Set(retryable.map(\.key)),
            ["rate_limited", "network_down", "incomplete", "unknown"]
        )
        for errorClass in retryable {
            XCTAssertTrue(errorClass.presentation.offeredActions.contains(.retry), "\(errorClass)")
        }
    }
}
