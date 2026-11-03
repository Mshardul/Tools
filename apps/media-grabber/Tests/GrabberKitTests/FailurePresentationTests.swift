@testable import GrabberKit
import XCTest

final class FailurePresentationTests: XCTestCase {
    private let cases: [ErrorClass] = [
        .rateLimited(), .geoBlocked, .private, .unavailable, .ageRestricted,
        .networkDown, .cookieReadFailed, .diskFull, .permissionDenied,
        .incomplete, .depMissing, .botCheck, .sabrGated, .formatsMissing,
        .potProviderDown, .passcodeRequired, .passcodeRejected, .unknown(raw: "ERROR: boom")
    ]

    func test_passcodeClassesHaveTheirSentencesAndNeverOfferPlainRetry() {
        XCTAssertEqual(ErrorClass.passcodeRequired.presentation.sentence, "This recording needs a passcode.")
        XCTAssertEqual(ErrorClass.passcodeRejected.presentation.sentence, "That passcode didn't work.")
        for errorClass in [ErrorClass.passcodeRequired, .passcodeRejected] {
            XCTAssertFalse(errorClass.isAutoRetryable, "\(errorClass)")
            XCTAssertEqual(errorClass.presentation.offeredActions, [.enterPasscode], "\(errorClass)")
        }
    }

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

    func test_noClassOffersSignInFromClassAlone() {
        for errorClass in cases {
            XCTAssertFalse(errorClass.presentation.offeredActions.contains(.retryWithCookies), "\(errorClass)")
        }
    }

    func test_botCheckSentenceNeverMentionsCookies() {
        XCTAssertFalse(ErrorClass.botCheck.presentation.sentence.lowercased().contains("cookie"))
    }

    func test_isAutoRetryableIsASubsetOfClassesOfferingRetry() {
        let retryable = cases.filter(\.isAutoRetryable)
        XCTAssertEqual(
            Set(retryable.map(\.key)),
            ["rate_limited", "network_down", "incomplete", "unknown", "bot_check", "formats_missing"]
        )
        for errorClass in retryable {
            XCTAssertTrue(errorClass.presentation.offeredActions.contains(.retry), "\(errorClass)")
        }
    }
}
