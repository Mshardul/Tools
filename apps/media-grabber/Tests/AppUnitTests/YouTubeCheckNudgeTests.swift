import GrabberKit
@testable import MediaGrabber
import XCTest

final class YouTubeCheckNudgeTests: XCTestCase {
    func testVisibleOnlyWhenSetupWasSkippedAndTheCheckIsMissing() {
        XCTAssertTrue(YouTubeCheckNudge.isVisible(
            onboardingComplete: true, shield: .missing, dismissed: false
        ))
        XCTAssertFalse(YouTubeCheckNudge.isVisible(
            onboardingComplete: false, shield: .missing, dismissed: false
        ))
        XCTAssertFalse(YouTubeCheckNudge.isVisible(
            onboardingComplete: true, shield: .down, dismissed: false
        ))
        XCTAssertFalse(YouTubeCheckNudge.isVisible(
            onboardingComplete: true, shield: .running(port: 4416), dismissed: false
        ))
        XCTAssertFalse(YouTubeCheckNudge.isVisible(
            onboardingComplete: true, shield: .missing, dismissed: true
        ))
        XCTAssertFalse(YouTubeCheckNudge.isVisible(
            onboardingComplete: true, shield: nil, dismissed: false
        ))
    }
}
