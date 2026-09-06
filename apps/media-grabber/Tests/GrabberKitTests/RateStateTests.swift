@testable import GrabberKit
import XCTest

final class RateStateTests: XCTestCase {
    func testStrikesAccessor() {
        XCTAssertEqual(RateState.normal.strikes, 0)
        XCTAssertEqual(RateState.cooldown(until: .now, strikes: 3).strikes, 3)
        XCTAssertEqual(RateState.circuitOpen(since: .now, strikes: 4).strikes, 4)
    }

    func testDisplayStateIsEquatable() {
        let original = HostRateDisplayState(
            state: .cooldown(until: Date(timeIntervalSince1970: 100), strikes: 1),
            lastErrorKey: "rate_limited",
            concurrencyReducedToOne: true
        )
        let copy = original
        XCTAssertEqual(original, copy)
    }
}
