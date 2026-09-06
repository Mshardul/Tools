@testable import GrabberKit
import XCTest

final class LogEventRateLimitTests: XCTestCase {
    func testCircuitOpenedFields() {
        let event = LogEvent.circuitOpened(host: "youtube", strikes: 4)
        XCTAssertEqual(event.key, "circuit.opened")
        XCTAssertEqual(event.fields["host"], "youtube")
        XCTAssertEqual(event.fields["strikes"], "4")
    }

    func testNetworkPathChangedFields() {
        XCTAssertEqual(LogEvent.networkPathChanged(online: false).fields["online"], "false")
        XCTAssertEqual(LogEvent.networkPathChanged(online: false).key, "network.path_changed")
    }

    func testCircuitResetByUser() {
        XCTAssertEqual(LogEvent.circuitReset(host: "youtube", byUser: true).fields["by_user"], "true")
    }

    func testHostRateStateChangedFields() {
        let event = LogEvent.hostRateStateChanged(host: "youtube", from: "normal", to: "cooldown")
        XCTAssertEqual(event.key, "host.rate_state_changed")
        XCTAssertEqual(event.fields["from"], "normal")
        XCTAssertEqual(event.fields["to"], "cooldown")
    }

    func testAdaptiveConcurrencyChanged() {
        let event = LogEvent.adaptiveConcurrencyChanged(from: 4, to: 1, reason: "throttle")
        XCTAssertEqual(event.fields["from"], "4")
        XCTAssertEqual(event.fields["to"], "1")
        XCTAssertEqual(event.fields["reason"], "throttle")
    }

    func testHostBlockOverriddenCarriesJobID() {
        let id = UUID()
        XCTAssertEqual(LogEvent.hostBlockOverridden(host: "youtube", jobID: id).jobID, id)
        XCTAssertEqual(LogEvent.hostBlockOverridden(host: "youtube", jobID: id).fields["host"], "youtube")
    }

    func testDeferReasonHostCooldownFields() {
        let event = LogEvent.jobDeferred(id: UUID(), until: .now, reason: .hostCooldown(host: "youtube", strikes: 2))
        XCTAssertEqual(event.fields["reason"], "host_cooldown")
        XCTAssertEqual(event.fields["strikes"], "2")
    }
}
