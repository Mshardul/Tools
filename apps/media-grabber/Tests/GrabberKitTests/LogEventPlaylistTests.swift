@testable import GrabberKit
import XCTest

final class LogEventPlaylistTests: XCTestCase {
    func testPlaylistEnqueuedFields() throws {
        let groupID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let event = LogEvent.playlistEnqueued(groupID: groupID, count: 12)

        XCTAssertEqual(event.key, "playlist.enqueued")
        XCTAssertEqual(event.category, .scheduler)
        XCTAssertEqual(event.fields["group_id"], groupID.uuidString)
        XCTAssertEqual(event.fields["count"], "12")
        XCTAssertNil(event.jobID)
    }
}
