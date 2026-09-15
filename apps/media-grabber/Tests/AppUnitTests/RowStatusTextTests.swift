@testable import GrabberKit
@testable import MediaGrabber
import XCTest

final class RowStatusTextTests: XCTestCase {
    private func snap(
        _ state: JobState,
        host: String = "https://youtube.com/x",
        cooldownUntil: Date? = nil,
        attempt: Int = 0
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
            availableActions: []
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

    func test_remark_botCheckWithoutVPN() {
        let remark = RowRemarkText.text(for: snap(.failed(.botCheck)), queuePosition: nil, rate: nil)
        XCTAssertEqual(remark, "Couldn't verify you. Try again, or add browser cookies in Preferences.")
    }

    func test_remark_botCheckWithVPN() {
        let remark = RowRemarkText.text(
            for: snap(.failed(.botCheck)),
            queuePosition: nil,
            rate: nil,
            vpnActive: true
        )
        XCTAssertEqual(remark, "Couldn't verify you. Turn off your VPN, or add browser cookies in Preferences.")
    }
}
