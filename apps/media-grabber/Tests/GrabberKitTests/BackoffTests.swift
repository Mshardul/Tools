@testable import GrabberKit
import XCTest

final class BackoffTests: XCTestCase {
    // jitter that always returns the top of the range → the ladder value itself
    private let maxJitter: (ClosedRange<Double>) -> Double = { $0.upperBound }

    func test_ladderValuesAtEachAttempt() {
        let expected: [Int: Double] = [1: 30, 2: 60, 3: 120, 4: 300, 5: 600]
        for (attempt, seconds) in expected {
            XCTAssertEqual(
                Backoff.delay(attempt: attempt, jitter: maxJitter),
                seconds,
                accuracy: 0.001
            )
        }
    }

    func test_attemptPastLadderReusesLastEntry() {
        XCTAssertEqual(Backoff.delay(attempt: 6, jitter: maxJitter), 600, accuracy: 0.001)
        XCTAssertEqual(Backoff.delay(attempt: 99, jitter: maxJitter), 600, accuracy: 0.001)
    }

    func test_retryAfterWinsOverLadderNoJitter() {
        XCTAssertEqual(
            Backoff.delay(attempt: 1, retryAfter: 45, jitter: maxJitter),
            45,
            accuracy: 0.001
        )
    }

    func test_retryAfterZeroFallsBackToLadder() {
        XCTAssertEqual(
            Backoff.delay(attempt: 2, retryAfter: 0, jitter: maxJitter),
            60,
            accuracy: 0.001
        )
    }

    func test_retryAfterAboveCapIsClamped() {
        XCTAssertEqual(
            Backoff.delay(attempt: 1, retryAfter: 5000, jitter: maxJitter),
            600,
            accuracy: 0.001
        )
    }

    func test_realRandomStaysInZeroToBase() {
        for _ in 0 ..< 500 {
            let value = Backoff.delay(attempt: 3)
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 120)
        }
    }

    func test_nonDefaultTuningLadderAndCapHonoured() {
        let tuning = EngineTuning(ytDlp: .default, backoffLadder: [10, 20, 30], backoffCap: 25)
        XCTAssertEqual(
            Backoff.delay(attempt: 1, tuning: tuning, jitter: maxJitter),
            10,
            accuracy: 0.001
        )
        XCTAssertEqual(
            Backoff.delay(attempt: 3, tuning: tuning, jitter: maxJitter),
            25,
            accuracy: 0.001
        )
    }
}
