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

    func testCooldownStateJob() {
        let text = RowStatusText.text(
            for: snap(.cooldown(until: future), cooldownUntil: future),
            maxAutoRetries: 5,
            rate: nil
        )
        XCTAssertEqual(text, "Cooling down")
    }

    func testCoolingHostQueuedJob() {
        let text = RowStatusText.text(for: snap(.queued), maxAutoRetries: 5, rate: cooling(future))
        XCTAssertEqual(text, "Cooling down")
    }

    func testCircuitOpenHostQueuedJob() {
        let text = RowStatusText.text(for: snap(.queued), maxAutoRetries: 5, rate: open)
        XCTAssertEqual(text, "Rate-limited — paused")
    }

    func testBackoffQueuedJob() {
        let text = RowStatusText.text(
            for: snap(.queued, cooldownUntil: future, attempt: 2),
            maxAutoRetries: 5,
            rate: nil
        )
        XCTAssertEqual(text, "Retrying")
    }

    func testPlainQueued() {
        XCTAssertEqual(RowStatusText.text(for: snap(.queued), maxAutoRetries: 5, rate: nil), "Queued")
    }

    func testWaitingForNetwork() {
        let text = RowStatusText.text(for: snap(.waitingForNetwork), maxAutoRetries: 5, rate: nil)
        XCTAssertEqual(text, "Waiting for network")
    }
}
