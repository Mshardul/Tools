@testable import GrabberKit
@testable import MediaGrabber
import XCTest

final class BotCheckCopyTests: XCTestCase {
    func testSentenceWithoutVPN() {
        XCTAssertEqual(
            BotCheckCopy.sentence(vpnActive: false),
            "Couldn't verify you. Try again, or add browser cookies in Preferences."
        )
    }

    func testSentenceWithVPN() {
        XCTAssertEqual(
            BotCheckCopy.sentence(vpnActive: true),
            "Couldn't verify you. Turn off your VPN, or add browser cookies in Preferences."
        )
    }

    func testProbeErrorHostBlocked() {
        XCTAssertEqual(
            AppModelDialogs.probeErrorMessage(for: .hostBlocked),
            "This site is cooling down. Try again in a moment."
        )
    }

    func testProbeErrorBotCheckDropsBrewLine() {
        let message = AppModelDialogs.probeErrorMessage(for: .botCheck)
        XCTAssertEqual(
            message,
            "Couldn't verify you. Try again, or add browser cookies in Preferences."
        )
        XCTAssertFalse(message.contains("brew"))
    }

    func testProbeErrorBotCheckVPN() {
        XCTAssertEqual(
            AppModelDialogs.probeErrorMessage(for: .botCheck, vpnActive: true),
            "Couldn't verify you. Turn off your VPN, or add browser cookies in Preferences."
        )
    }
}
