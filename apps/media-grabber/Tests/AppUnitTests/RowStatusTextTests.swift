@testable import GrabberKit
@testable import MediaGrabber
import XCTest

final class RowStatusTextTests: XCTestCase {
    private func snap(
        _ state: JobState,
        host: String = "https://youtube.com/x",
        cooldownUntil: Date? = nil,
        attempt: Int = 0,
        probeWaitUntil: Date? = nil,
        advice: SignInAdvice = .none
    ) -> JobSnapshot {
        JobSnapshot(
            id: UUID(),
            url: host,
            rateHost: RateHost(urlString: host),
            title: "Clip",
            state: state,
            progress: nil,
            kind: .video(maxHeight: 1080),
            durationSeconds: nil,
            extractor: nil,
            addedAt: .now,
            finishedAt: nil,
            destFolder: URL(fileURLWithPath: "/tmp"),
            outputFiles: [],
            sizeBytes: nil,
            actualQuality: nil,
            attempt: attempt,
            cooldownUntil: cooldownUntil,
            playerClientUsed: nil,
            playlistGroupID: nil,
            integrityVerdict: nil,
            availableActions: [],
            probeWaitUntil: probeWaitUntil,
            signInAdvice: advice
        )
    }

    private let future = Date().addingTimeInterval(120)

    private func cooling(_ deadline: Date) -> HostRateDisplayState {
        HostRateDisplayState(
            state: .cooldown(until: deadline, strikes: 1),
            lastErrorKey: "rate_limited",
            concurrencyReducedToOne: true
        )
    }

    private let open = HostRateDisplayState(
        state: .circuitOpen(since: Date(timeIntervalSince1970: 1000), strikes: 4),
        lastErrorKey: nil,
        concurrencyReducedToOne: true
    )

    // MARK: - Status is 1:1 with JobState, never invented

    func test_queued_isPlainQueued() {
        XCTAssertEqual(RowStatusText.text(for: snap(.queued)), "Queued")
    }

    func test_queued_stillPlainQueued_evenWhenHostCooling() {
        XCTAssertEqual(RowStatusText.text(for: snap(.queued)), "Queued")
    }

    func test_cooldownState_isCoolingDown() {
        XCTAssertEqual(
            RowStatusText.text(for: snap(.cooldown(until: future), cooldownUntil: future)),
            "Cooling down"
        )
    }

    func test_waitingForNetwork() {
        XCTAssertEqual(RowStatusText.text(for: snap(.waitingForNetwork)), "Waiting for network")
    }

    func test_failed_isPlainFailed_noSentence() {
        XCTAssertEqual(RowStatusText.text(for: snap(.failed(.botCheck))), "Failed")
    }

    func test_running_isDownloading() {
        XCTAssertEqual(RowStatusText.text(for: snap(.running)), "Downloading")
    }

    // MARK: - Remark carries the detail Status no longer invents

    func test_remark_plainQueued_noPositionGiven_isEmpty() {
        let remark = RowRemarkText.text(for: snap(.queued), queuePosition: nil, rate: nil)
        XCTAssertEqual(remark, "")
    }

    func test_remark_queuedWithPosition_isHashN() {
        let remark = RowRemarkText.text(for: snap(.queued), queuePosition: 3, rate: nil)
        XCTAssertEqual(remark, "#3")
    }

    func test_remark_coolingHostQueuedJob_isWaitReason() {
        let remark = RowRemarkText.text(for: snap(.queued), queuePosition: 1, rate: cooling(future))
        XCTAssertTrue(remark.hasPrefix("Try again in"))
    }

    func test_remark_circuitOpenHostQueuedJob_isRateLimited() {
        let remark = RowRemarkText.text(for: snap(.queued), queuePosition: 1, rate: open)
        XCTAssertEqual(remark, "Rate-limited")
    }

    func test_remark_backoffQueuedJob_isWaitReason() {
        let remark = RowRemarkText.text(
            for: snap(.queued, cooldownUntil: future, attempt: 2),
            queuePosition: nil,
            rate: nil
        )
        XCTAssertTrue(remark.hasPrefix("Try again in"))
    }

    func test_remark_waitingForNetwork_isNoConnection() {
        let remark = RowRemarkText.text(for: snap(.waitingForNetwork), queuePosition: nil, rate: nil)
        XCTAssertEqual(remark, "No connection")
    }

    func test_remark_cooldown_isCountdown() {
        let remark = RowRemarkText.text(
            for: snap(.cooldown(until: future), cooldownUntil: future),
            queuePosition: nil,
            rate: nil
        )
        XCTAssertTrue(remark.hasPrefix("Try again in"))
    }

    func test_remark_running_isEmpty() {
        let remark = RowRemarkText.text(for: snap(.running), queuePosition: nil, rate: nil)
        XCTAssertEqual(remark, "")
    }

    func test_remark_probingWaitSlot_showsCountdown() {
        let remark = RowRemarkText.text(
            for: snap(.probing, probeWaitUntil: future),
            queuePosition: nil,
            rate: nil
        )
        XCTAssertTrue(remark.hasPrefix("Waiting for probe slot · "))
    }

    func test_remark_probingWithoutWait_isEmpty() {
        let remark = RowRemarkText.text(for: snap(.probing), queuePosition: nil, rate: nil)
        XCTAssertEqual(remark, "")
    }

    func test_remark_botCheckOnYouTube_shieldRunning() {
        let remark = RowRemarkText.text(
            for: snap(.failed(.botCheck), advice: .suggest),
            queuePosition: nil, rate: nil, shieldStatus: .running(port: 1234)
        )
        XCTAssertEqual(
            remark,
            "YouTube didn't accept this request. Try again, or sign in with your browser in Preferences."
        )
    }

    func test_remark_botCheckOnYouTube_shieldMissing_blamesShield() {
        let remark = RowRemarkText.text(
            for: snap(.failed(.botCheck), advice: .suggest), queuePosition: nil, rate: nil, shieldStatus: .missing
        )
        XCTAssertTrue(remark.contains("isn't set up"))
    }

    func test_remark_botCheckOnOtherSite_neverBlamesShield() {
        let remark = RowRemarkText.text(
            for: snap(.failed(.botCheck), host: "https://vimeo.com/1"),
            queuePosition: nil,
            rate: nil,
            shieldStatus: .missing
        )
        XCTAssertTrue(remark.hasPrefix("This site didn't accept"))
        XCTAssertFalse(remark.contains("shield"))
    }

    // MARK: - Failure remarks

    private func failedRemark(
        _ errorClass: ErrorClass,
        host: String = "https://youtube.com/x",
        advice: SignInAdvice
    ) -> String {
        RowRemarkText.text(for: snap(.failed(errorClass), host: host, advice: advice), queuePosition: nil, rate: nil)
    }

    func test_remark_ageRestricted_unconfigured_suggestsSignIn() {
        XCTAssertEqual(
            failedRemark(.ageRestricted, advice: .suggest),
            "This video is age-restricted. Signing in with your browser may let you download it."
        )
    }

    func test_remark_ageRestricted_configured_asksToCheckBrowser() {
        XCTAssertEqual(
            failedRemark(.ageRestricted, advice: .checkBrowser),
            "This video is age-restricted. Make sure your browser is signed in to an account that can watch it."
        )
    }

    func test_remark_private_unconfigured_suggestsSignIn() {
        XCTAssertEqual(
            failedRemark(.private, host: "https://vimeo.com/1", advice: .suggest),
            "This video is private. If you have access, signing in with your browser may let you download it."
        )
    }

    func test_remark_private_configured_asksToCheckBrowser() {
        XCTAssertEqual(
            failedRemark(.private, advice: .checkBrowser),
            "This video is private. Make sure your browser is signed in to an account that has access."
        )
    }

    func test_remark_formatsMissingAndRateLimited_neverMentionSignIn() {
        for errorClass in [ErrorClass.formatsMissing, .rateLimited()] {
            let remark = failedRemark(errorClass, advice: .none).lowercased()
            XCTAssertFalse(remark.contains("sign"))
            XCTAssertFalse(remark.contains("cookie"))
        }
    }

    func test_remark_nonYouTubeBotCheck_neverMentionsSignIn() {
        let remark = failedRemark(.botCheck, host: "https://vimeo.com/1", advice: .none)
        XCTAssertEqual(remark, "This site didn't accept this request. Try again later, or turn off your VPN.")
    }
}
