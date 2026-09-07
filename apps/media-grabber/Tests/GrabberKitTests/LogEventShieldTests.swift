@testable import GrabberKit
import XCTest

final class LogEventShieldTests: XCTestCase {
    func testShieldStarted() {
        let event = LogEvent.shieldStarted(port: 4416)
        XCTAssertEqual(event.key, "shield.started")
        XCTAssertEqual(event.category, .deps)
        XCTAssertEqual(event.fields["port"], "4416")
        XCTAssertNil(event.jobID)
    }

    func testShieldExited() {
        let event = LogEvent.shieldExited(code: 1)
        XCTAssertEqual(event.key, "shield.exited")
        XCTAssertEqual(event.category, .deps)
        XCTAssertEqual(event.fields["code"], "1")
    }

    func testShieldRestarted() {
        let event = LogEvent.shieldRestarted(reason: "health_timeout")
        XCTAssertEqual(event.key, "shield.restarted")
        XCTAssertEqual(event.category, .deps)
        XCTAssertEqual(event.fields["reason"], "health_timeout")
    }

    func testShieldMissing() {
        let event = LogEvent.shieldMissing
        XCTAssertEqual(event.key, "shield.missing")
        XCTAssertEqual(event.category, .deps)
        XCTAssertTrue(event.fields.isEmpty)
    }
}
