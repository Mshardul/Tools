@testable import GrabberKit
import XCTest

final class ErrorSignaturesTests: XCTestCase {
    private func classify(_ line: String) -> ErrorClass? {
        ProgressParser.classifyStderr(line)
    }

    func test_rateLimitedSignatures() {
        XCTAssertEqual(classify("ERROR: HTTP Error 429: Too Many Requests"), .rateLimited())
        XCTAssertEqual(classify("WARNING: The download speed is below the minimum"), .rateLimited())
        XCTAssertEqual(
            classify("ERROR: Download speed 12.00KiB/s below throttle limit"),
            .rateLimited()
        )
    }

    func test_geoBlocked() {
        XCTAssertEqual(
            classify("ERROR: The uploader has not made this video available in your country"),
            .geoBlocked
        )
        XCTAssertEqual(
            classify(
                "ERROR: This video contains content from X, who has blocked it in your country"
            ),
            .geoBlocked
        )
    }

    func test_private_unavailable_ageRestricted() {
        XCTAssertEqual(
            classify("ERROR: Private video. Sign in if you've been granted access to this video"),
            .private
        )
        XCTAssertEqual(classify("ERROR: Video unavailable"), .unavailable)
        XCTAssertEqual(classify("ERROR: This video has been removed by the uploader"), .unavailable)
        XCTAssertEqual(classify("ERROR: Sign in to confirm your age"), .ageRestricted)
    }

    func test_networkFirstThenTableThenErrorFallthroughThenNil() {
        XCTAssertEqual(
            classify(
                "ERROR: Unable to download webpage: <urlopen error [Errno 8] "
                    + "nodename nor servname provided>"
            ),
            .networkDown
        )
        XCTAssertEqual(
            classify("ERROR: something we have no signature for"),
            .unknown(raw: "ERROR: something we have no signature for")
        )
        XCTAssertNil(classify("[download] 42% of 10MiB"))
    }

    func test_cookieReadFailed_eachFragmentGroupClassifies() {
        let lines = [
            "ERROR: could not find chrome cookies database in \"...\"",
            "ERROR: Permission denied while opening Cookies for Safari",
            "ERROR: Failed to decrypt with DPAPI",
            "ERROR: unable to open database file (cookies)",
            "ERROR: could not copy Chrome's cookie database",
            "ERROR: You must provide at least one --cookies or --cookies-from-browser"
        ]
        for line in lines {
            XCTAssertEqual(classify(line), .cookieReadFailed, line)
        }
    }

    func test_cookieReadFailed_winsOverPrivate_whenBothPresent() {
        XCTAssertEqual(
            classify("ERROR: Private video. could not find firefox cookies database"),
            .cookieReadFailed
        )
    }

    func test_retryAfterIntegerParsedIntoRateLimited() {
        XCTAssertEqual(
            classify("ERROR: HTTP Error 429: Too Many Requests. Retry-After: 90"),
            .rateLimited(retryAfterSeconds: 90)
        )
    }

    func test_retryAfterHttpDateIgnored() {
        XCTAssertEqual(
            classify("ERROR: HTTP Error 429. Retry-After: Wed, 21 Oct 2025 07:28:00 GMT"),
            .rateLimited(retryAfterSeconds: nil)
        )
    }
}
