@testable import MediaGrabber
import XCTest

@MainActor
final class NotificationRouterTests: XCTestCase {
    func test_notifyJobFailed_recordedByFake() async {
        let router = FakeNotificationRouter()
        await router.notifyJobFailed(title: "Clip", reason: "No internet connection.")
        XCTAssertEqual(router.notifiedFailures.count, 1)
        XCTAssertEqual(router.notifiedFailures.first?.title, "Clip")
        XCTAssertEqual(router.notifiedFailures.first?.reason, "No internet connection.")
    }
}
