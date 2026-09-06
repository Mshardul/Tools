@testable import GrabberKit
@testable import MediaGrabber
import XCTest

@MainActor
final class HealthControllerTests: XCTestCase {
    private func snapshot(
        online: Bool,
        summary: [RateHost: HostRateDisplayState]
    ) -> QueueSnapshot {
        QueueSnapshot(
            jobs: [],
            revision: 1,
            queueHalt: nil,
            generatedAt: .now,
            hostRateSummary: summary,
            isOnline: online
        )
    }

    func testOnlineChipAlwaysPresent() {
        let controller = HealthController()
        controller.update(snapshot: snapshot(online: true, summary: [:]), now: .now)
        XCTAssertEqual(controller.chips.count, 1)
        XCTAssertEqual(controller.chips[0].label, "online")
    }

    func testOfflineChipLabel() {
        let controller = HealthController()
        controller.update(snapshot: snapshot(online: false, summary: [:]), now: .now)
        XCTAssertEqual(controller.chips[0].label, "offline")
    }

    func testCooldownChipCarriesDeadlineAsData() {
        let yt = RateHost(urlString: "https://youtube.com/x")
        let now = Date(timeIntervalSince1970: 1000)
        let summary = [yt: HostRateDisplayState(
            state: .cooldown(until: now.addingTimeInterval(134), strikes: 1),
            lastErrorKey: "rate_limited",
            concurrencyReducedToOne: true
        )]
        let controller = HealthController()
        controller.update(snapshot: snapshot(online: true, summary: summary), now: now)
        XCTAssertEqual(controller.chips.count, 2)
        let cooldown = controller.chips[1]
        XCTAssertEqual(cooldown.label, "YouTube")
        XCTAssertEqual(cooldown.countdownUntil, now.addingTimeInterval(134))
        XCTAssertEqual(cooldown.interaction, .popover(.hostRate))
    }

    func testMultipleHostsCollapseToOneChip() {
        let youtube = RateHost(urlString: "https://youtube.com/x")
        let vimeo = RateHost(urlString: "https://vimeo.com/1")
        let now = Date(timeIntervalSince1970: 1000)
        let display = HostRateDisplayState(
            state: .cooldown(until: now.addingTimeInterval(60), strikes: 1),
            lastErrorKey: nil,
            concurrencyReducedToOne: false
        )
        let controller = HealthController()
        controller.update(
            snapshot: snapshot(online: true, summary: [youtube: display, vimeo: display]),
            now: now
        )
        XCTAssertEqual(controller.chips.count, 2)
        XCTAssertEqual(controller.chips[1].label, "2 sites cooling down")
    }

    func testCircuitOpenChipLabel() {
        let yt = RateHost(urlString: "https://youtube.com/x")
        let now = Date(timeIntervalSince1970: 1000)
        let summary = [yt: HostRateDisplayState(
            state: .circuitOpen(since: now, strikes: 4),
            lastErrorKey: "rate_limited",
            concurrencyReducedToOne: true
        )]
        let controller = HealthController()
        controller.update(snapshot: snapshot(online: true, summary: summary), now: now)
        XCTAssertEqual(controller.chips[1].label, "YouTube — paused")
    }
}
