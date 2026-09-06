@testable import GrabberKit
import XCTest

final class RatePolicyTests: XCTestCase {
    // ladder [1, 2], threshold 3, no jitter (always the max of the range)
    private let tuning = EngineTuning(
        ytDlp: .default,
        backoffLadder: [1, 2],
        backoffCap: 600,
        circuitStrikeThreshold: 3,
        adaptiveConcurrencyStart: 2,
        cleanStreakToRaise: 5,
        networkOfflineGraceSeconds: 2,
        networkOnlineSettleSeconds: 2,
        concurrentFragmentsNormal: 4,
        concurrentFragmentsThrottled: 1
    )
    private let noJitter: (ClosedRange<Double>) -> Double = { $0.upperBound }
    private let t0 = Date(timeIntervalSince1970: 1000)

    private func next(_ state: RateState, _ event: RatePolicyEvent, at now: Date) -> RateState {
        RatePolicy.next(state: state, event: event, now: now, tuning: tuning, jitter: noJitter)
    }

    func testNormalStrikeEntersCooldownRungOne() {
        let result = next(.normal, .strike(retryAfter: nil), at: t0)
        guard case let .cooldown(until, strikes) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(strikes, 1)
        XCTAssertEqual(until, t0.addingTimeInterval(1))
    }

    func testStrikeBeforeDeadlineIsIgnored() {
        let cooling = RateState.cooldown(until: t0.addingTimeInterval(30), strikes: 1)
        let result = next(cooling, .strike(retryAfter: nil), at: t0)
        XCTAssertEqual(result, cooling)
    }

    func testStrikeAfterDeadlineEscalatesThenTripsCircuit() {
        var state = RateState.cooldown(until: t0, strikes: 1)
        state = next(state, .strike(retryAfter: nil), at: t0.addingTimeInterval(5))
        guard case let .cooldown(_, strikes) = state else { return XCTFail("\(state)") }
        XCTAssertEqual(strikes, 2)

        state = next(state, .strike(retryAfter: nil), at: t0.addingTimeInterval(20))
        guard case let .circuitOpen(_, strikes3) = state else { return XCTFail("\(state)") }
        XCTAssertEqual(strikes3, 3)
    }

    func testCleanSuccessResetsFromCooldown() {
        let result = next(.cooldown(until: t0, strikes: 2), .cleanSuccess, at: t0)
        XCTAssertEqual(result, .normal)
    }

    func testUserResetFromCircuitOpen() {
        let result = next(.circuitOpen(since: t0, strikes: 4), .userReset, at: t0)
        XCTAssertEqual(result, .normal)
    }

    func testRetryAfterOverridesLadder() {
        let result = next(.normal, .strike(retryAfter: 120), at: t0)
        guard case let .cooldown(until, _) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(until, t0.addingTimeInterval(120))
    }
}
