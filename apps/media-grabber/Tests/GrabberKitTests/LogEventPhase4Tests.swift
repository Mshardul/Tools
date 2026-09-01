@testable import GrabberKit
import XCTest

final class LogEventPhase4Tests: XCTestCase {
    func test_jobDeferredBackoffFields() {
        let until = Date(timeIntervalSince1970: 1000)
        let event = LogEvent.jobDeferred(id: UUID(), until: until, reason: .backoff(attempt: 2))
        XCTAssertEqual(event.fields["reason"], "backoff")
        XCTAssertEqual(event.fields["attempt"], "2")
        XCTAssertEqual(event.fields["until"], ISO8601DateFormatter().string(from: until))
    }

    func test_jobRetried() {
        let event = LogEvent.jobRetried(id: UUID())
        XCTAssertEqual(event.key, "job.retried")
        XCTAssertEqual(event.category, .engine)
        XCTAssertTrue(event.fields.isEmpty)
    }

    func test_showLogTargetMissing() {
        let id = UUID()
        let event = LogEvent.showLogTargetMissing(jobID: id)
        XCTAssertEqual(event.key, "show_log.target_missing")
        XCTAssertEqual(event.category, .ui)
        XCTAssertEqual(event.fields["job_id"], id.uuidString)
    }
}
