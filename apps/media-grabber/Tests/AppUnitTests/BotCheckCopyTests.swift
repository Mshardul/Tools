@testable import GrabberKit
@testable import MediaGrabber
import XCTest

final class BotCheckCopyTests: XCTestCase {
    private let running = ShieldStatus.running(port: 1234)

    func testYouTubeShieldRunning_suggestsRetryOrSignIn() {
        XCTAssertEqual(
            BotCheckCopy.sentence(vpnActive: false, shieldStatus: running, isYouTube: true, advice: .suggest),
            "YouTube didn't accept this request. Try again, or sign in with your browser in Preferences."
        )
    }

    func testYouTubeShieldRunningWithVPN_suggestsVPNOff() {
        XCTAssertEqual(
            BotCheckCopy.sentence(vpnActive: true, shieldStatus: running, isYouTube: true, advice: .suggest),
            "YouTube didn't accept this request. Try turning off your VPN, or sign in with your browser in Preferences."
        )
    }

    func testYouTubeShieldDown_blamesShieldAndAsksForNothingElse() {
        let message = BotCheckCopy.sentence(vpnActive: false, shieldStatus: .down, isYouTube: true, advice: .suggest)
        XCTAssertEqual(message, "YouTube didn't accept this request because the bot-check shield stopped working.")
        XCTAssertFalse(message.contains("sign in"))
    }

    func testYouTubeShieldMissing_saysNotSetUpAndNeverMentionsCommands() {
        let message = BotCheckCopy.sentence(vpnActive: false, shieldStatus: .missing, isYouTube: true, advice: .suggest)
        XCTAssertTrue(message.contains("isn't set up"))
        XCTAssertFalse(message.contains("pipx"))
        XCTAssertFalse(message.contains("sign in"))
    }

    func testOtherSite_neverBlamesTheShieldWhateverItsState() {
        for status in [ShieldStatus.running(port: 1), .down, .missing] {
            let message = BotCheckCopy.sentence(
                vpnActive: false, shieldStatus: status, isYouTube: false, advice: .none
            )
            XCTAssertEqual(
                message,
                "This site didn't accept this request. Try again later, or turn off your VPN."
            )
            XCTAssertFalse(message.contains("shield"))
            XCTAssertFalse(message.lowercased().contains("sign"))
        }
    }

    func testYouTubeConfigured_asksToCheckTheBrowser() {
        XCTAssertEqual(
            BotCheckCopy.sentence(vpnActive: false, shieldStatus: running, isYouTube: true, advice: .checkBrowser),
            "YouTube didn't accept this request. Try again, or check that your browser is signed in to YouTube."
        )
    }

    func testProbeErrorHostBlocked() {
        XCTAssertEqual(
            AppModelDialogs.probeErrorMessage(for: .hostBlocked),
            "This site is cooling down. Try again in a moment."
        )
    }

    func testProbeErrorBotCheckUsesSiteAwareCopy() {
        XCTAssertEqual(
            AppModelDialogs.probeErrorMessage(for: .botCheck, shieldStatus: running, isYouTube: true, advice: .suggest),
            "YouTube didn't accept this request. Try again, or sign in with your browser in Preferences."
        )
        XCTAssertTrue(
            AppModelDialogs.probeErrorMessage(for: .botCheck, shieldStatus: .missing, isYouTube: true, advice: .suggest)
                .contains("isn't set up")
        )
    }

    func testProbeErrorCookieReadFailed_isPlainLanguage() {
        let message = AppModelDialogs.probeErrorMessage(for: .cookieReadFailed)
        XCTAssertTrue(message.contains("sign-in"))
        XCTAssertFalse(message.lowercased().contains("cookie"))
    }

    func testProbeErrorAgeRestricted_suggestsSignInWithoutRawText() {
        let message = AppModelDialogs.probeErrorMessage(for: .ageRestricted, advice: .suggest)
        XCTAssertEqual(message, "This video is age-restricted. Signing in with your browser may let you download it.")
        XCTAssertFalse(message.lowercased().contains("yt-dlp"))
    }

    func testProbeErrorPrivate_configuredAsksToCheckBrowser() {
        XCTAssertEqual(
            AppModelDialogs.probeErrorMessage(for: .private, advice: .checkBrowser),
            "This video is private. Make sure your browser is signed in to an account that has access."
        )
    }

    func testProbeErrorBotCheckOnOtherSite_hasNoSignInMention() {
        let message = AppModelDialogs.probeErrorMessage(for: .botCheck, shieldStatus: .missing, isYouTube: false)
        XCTAssertFalse(message.lowercased().contains("sign"))
    }
}
