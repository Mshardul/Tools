@testable import GrabberKit
import XCTest

final class PlayerClientRotationTests: XCTestCase {
    func testFirstUnburnedClient() {
        XCTAssertEqual(PlayerClientRotation.client(order: ["tv", "ios"], burned: []), "tv")
        XCTAssertEqual(PlayerClientRotation.client(order: ["tv", "ios"], burned: ["tv"]), "ios")
    }

    func testExhaustedOrderUsesTheLastClient() {
        XCTAssertEqual(PlayerClientRotation.client(order: ["tv", "ios"], burned: ["tv", "ios"]), "ios")
    }

    func testEmptyOrderUsesTv() {
        XCTAssertEqual(PlayerClientRotation.client(order: ["", " "], burned: []), "tv")
    }

    func testBundledOrder() {
        XCTAssertEqual(
            PlayerClientRotation.bundled,
            ["tv", "ios", "tv_embedded", "mweb", "web_safari"]
        )
    }
}
