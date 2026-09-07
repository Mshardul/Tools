@testable import GrabberKit
import XCTest

final class YouTubeErrorClassificationTests: XCTestCase {
    private func classify(_ line: String) -> ErrorClass? {
        ProgressParser.classifyStderr(line)
    }

    func testBotCheckSignatures() {
        XCTAssertEqual(
            classify("ERROR: Sign in to confirm you're not a bot"),
            .botCheck
        )
        XCTAssertEqual(
            classify("ERROR: The page needs to be reloaded"),
            .botCheck
        )
        XCTAssertEqual(classify("ERROR: HTTP Error 403"), .botCheck)
    }

    func testAgeRestrictedStillWinsOverBotCheckPrefix() {
        XCTAssertEqual(
            classify("ERROR: Sign in to confirm your age"),
            .ageRestricted
        )
    }

    func testSabrGatedFromFixture() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "ytdlp-stderr-sabr", withExtension: "txt")
        )
        let stderr = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(classify(stderr), .sabrGated)
    }

    func testFormatsMissingFromFixture() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "ytdlp-stderr-formats-missing", withExtension: "txt")
        )
        let stderr = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(classify(stderr), .formatsMissing)
    }

    func testSabrBeatsFormatsMissingWhenBothPresent() {
        XCTAssertEqual(
            classify("ERROR: only images are available. requested format is not available"),
            .sabrGated
        )
    }

    func testPresentationSentencesAndActions() {
        XCTAssertEqual(
            ErrorClass.botCheck.presentation.sentence,
            "Couldn't verify you. Try again, or add browser cookies in Preferences."
        )
        XCTAssertEqual(
            ErrorClass.botCheck.presentation.offeredActions,
            [.retry, .retryWithCookies]
        )
        XCTAssertEqual(
            ErrorClass.sabrGated.presentation.sentence,
            "YouTube isn't offering a downloadable video for this link."
        )
        XCTAssertEqual(ErrorClass.sabrGated.presentation.offeredActions, [])
        XCTAssertEqual(
            ErrorClass.formatsMissing.presentation.sentence,
            "The quality you picked isn't available for this video."
        )
        XCTAssertEqual(
            ErrorClass.formatsMissing.presentation.offeredActions,
            [.retry, .retryWithCookies]
        )
        XCTAssertEqual(
            ErrorClass.potProviderDown.presentation.sentence,
            "Bot-check protection is offline."
        )
        XCTAssertEqual(ErrorClass.potProviderDown.presentation.offeredActions, [.retry])
    }

    func testAutoRetryableYouTubeCases() {
        XCTAssertTrue(ErrorClass.botCheck.isAutoRetryable)
        XCTAssertTrue(ErrorClass.formatsMissing.isAutoRetryable)
        XCTAssertFalse(ErrorClass.sabrGated.isAutoRetryable)
        XCTAssertFalse(ErrorClass.potProviderDown.isAutoRetryable)
    }

    func testHostBlockedMapsToRateLimited() {
        XCTAssertEqual(DownloadEngine.errorClass(for: .hostBlocked), .rateLimited())
    }

    func testAudioOnlyVideoExitIsFormatsMissing() {
        XCTAssertEqual(
            DownloadEngine.resolvedExitClass(
                kind: .video(maxHeight: 1080),
                lastError: nil,
                sawAudioOnly: true
            ),
            .formatsMissing
        )
    }

    func testSabrGatedNotOverriddenByAudioOnly() {
        XCTAssertEqual(
            DownloadEngine.resolvedExitClass(
                kind: .video(maxHeight: 1080),
                lastError: .sabrGated,
                sawAudioOnly: true
            ),
            .sabrGated
        )
    }
}
