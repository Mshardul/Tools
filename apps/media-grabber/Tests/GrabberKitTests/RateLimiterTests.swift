@testable import GrabberKit
import XCTest

final class RateLimiterTests: XCTestCase {
    private func tuning(threshold: Int = 3, streak: Int = 5) -> EngineTuning {
        EngineTuning(
            ytDlp: .default, backoffLadder: [1, 2], backoffCap: 600,
            circuitStrikeThreshold: threshold, adaptiveConcurrencyStart: 2,
            cleanStreakToRaise: streak, networkOfflineGraceSeconds: 2,
            networkOnlineSettleSeconds: 2, concurrentFragmentsNormal: 4,
            concurrentFragmentsThrottled: 1
        )
    }

    private let yt = RateHost(urlString: "https://youtube.com/watch?v=x")
    private let vimeo = RateHost(urlString: "https://vimeo.com/1")
    private let t0 = Date(timeIntervalSince1970: 1000)

    func testAdaptiveCapStartsClamped() {
        XCTAssertEqual(
            RateLimiter(tuning: tuning(), preferencesCap: 6).adaptiveCap(for: yt), 2
        )
        XCTAssertEqual(
            RateLimiter(tuning: tuning(), preferencesCap: 1).adaptiveCap(for: yt), 1
        )
    }

    func testCleanStreakRaisesOnlyThatHost() {
        var limiter = RateLimiter(tuning: tuning(streak: 3), preferencesCap: 4)
        for _ in 0 ..< 3 {
            limiter.recordCleanSuccess(host: yt, now: t0)
        }
        XCTAssertEqual(limiter.adaptiveCap(for: yt), 3)
        XCTAssertEqual(limiter.adaptiveCap(for: vimeo), 2)
        for _ in 0 ..< 3 {
            limiter.recordCleanSuccess(host: yt, now: t0)
        }
        XCTAssertEqual(limiter.adaptiveCap(for: yt), 4)
        for _ in 0 ..< 3 {
            limiter.recordCleanSuccess(host: yt, now: t0)
        }
        XCTAssertEqual(limiter.adaptiveCap(for: yt), 4, "clamped at prefs cap")
        XCTAssertEqual(limiter.adaptiveCap(for: vimeo), 2)
    }

    func testStrikeOnOneHostDoesNotSerialiseAnother() {
        var limiter = RateLimiter(tuning: tuning(streak: 3), preferencesCap: 6)
        for _ in 0 ..< 3 {
            limiter.recordCleanSuccess(host: yt, now: t0)
        }
        XCTAssertEqual(limiter.adaptiveCap(for: yt), 3)
        XCTAssertEqual(limiter.adaptiveCap(for: vimeo), 2)
        limiter.recordStrike(host: yt, retryAfter: nil, lastErrorKey: "rate_limited", now: t0)
        XCTAssertEqual(limiter.adaptiveCap(for: yt), 1)
        XCTAssertEqual(limiter.adaptiveCap(for: vimeo), 2)
        XCTAssertTrue(limiter.concurrencyReducedToOne(for: yt))
        XCTAssertFalse(limiter.concurrencyReducedToOne(for: vimeo))
        limiter.recordCleanSuccess(host: yt, now: t0)
        XCTAssertEqual(limiter.adaptiveCap(for: yt), 1, "streak restarted from zero")
    }

    func testBlockedTrueWhileCoolingFalseAfterDeadline() {
        var limiter = RateLimiter(tuning: tuning(), preferencesCap: 6)
        limiter.recordStrike(host: yt, retryAfter: 30, lastErrorKey: "rate_limited", now: t0)
        XCTAssertTrue(limiter.blocked(host: yt, now: t0.addingTimeInterval(10)))
        XCTAssertFalse(limiter.blocked(host: yt, now: t0.addingTimeInterval(31)))
        XCTAssertFalse(limiter.blocked(host: vimeo, now: t0.addingTimeInterval(10)))
    }

    func testCircuitTripAndReset() {
        var limiter = RateLimiter(tuning: tuning(threshold: 2), preferencesCap: 6)
        limiter.recordStrike(host: yt, retryAfter: 1, lastErrorKey: "rate_limited", now: t0)
        limiter.recordStrike(
            host: yt, retryAfter: 1, lastErrorKey: "rate_limited", now: t0.addingTimeInterval(5)
        )
        XCTAssertEqual(limiter.circuitOpenHosts, [yt])
        XCTAssertTrue(limiter.blocked(host: yt, now: t0.addingTimeInterval(999)))
        limiter.resetCircuit(host: yt, now: t0.addingTimeInterval(10))
        XCTAssertTrue(limiter.circuitOpenHosts.isEmpty)
        XCTAssertFalse(limiter.blocked(host: yt, now: t0.addingTimeInterval(999)))
    }

    func testResetCircuitUsesUserResetPolicyPath() {
        var limiter = RateLimiter(tuning: tuning(threshold: 2), preferencesCap: 6)
        limiter.recordStrike(host: yt, retryAfter: 1, lastErrorKey: "rate_limited", now: t0)
        limiter.recordStrike(
            host: yt, retryAfter: 1, lastErrorKey: "rate_limited", now: t0.addingTimeInterval(5)
        )
        XCTAssertEqual(limiter.circuitOpenHosts, [yt])
        limiter.resetCircuit(host: yt, now: t0.addingTimeInterval(10))
        XCTAssertTrue(limiter.circuitOpenHosts.isEmpty)
        XCTAssertEqual(limiter.state(for: yt), .normal)
        XCTAssertNil(limiter.displaySummary(now: t0.addingTimeInterval(999))[yt])
    }

    func testCleanSuccessResetsStrikeSoLadderRestarts() {
        var limiter = RateLimiter(tuning: tuning(threshold: 3), preferencesCap: 6)
        limiter.recordStrike(host: yt, retryAfter: 1, lastErrorKey: "rate_limited", now: t0)
        limiter.recordCleanSuccess(host: yt, now: t0.addingTimeInterval(5))
        limiter.recordStrike(
            host: yt, retryAfter: 1, lastErrorKey: "rate_limited", now: t0.addingTimeInterval(10)
        )
        guard case let .cooldown(_, strikes) = limiter.state(for: yt) else {
            return XCTFail("\(limiter.state(for: yt))")
        }
        XCTAssertEqual(strikes, 1, "clean success reset the count")
    }

    func testSetPreferencesCapReclampsWithoutJumping() {
        var limiter = RateLimiter(tuning: tuning(streak: 3), preferencesCap: 6)
        for _ in 0 ..< 3 {
            limiter.recordCleanSuccess(host: yt, now: t0)
        } // cap 3
        limiter.setPreferencesCap(2)
        XCTAssertEqual(limiter.adaptiveCap(for: yt), 2)
        limiter.setPreferencesCap(6)
        XCTAssertEqual(limiter.adaptiveCap(for: yt), 2, "a raise does not jump the cap")
        XCTAssertEqual(limiter.adaptiveCap(for: vimeo), 2, "untouched host stays at start")
    }

    func testDisplaySummaryOnlyCoolingOrOpenHosts() {
        var limiter = RateLimiter(tuning: tuning(), preferencesCap: 6)
        limiter.recordStrike(host: yt, retryAfter: 30, lastErrorKey: "rate_limited", now: t0)
        let summary = limiter.displaySummary(now: t0.addingTimeInterval(5))
        XCTAssertEqual(summary.keys.map(\.canonical), ["youtube"])
        XCTAssertEqual(summary[yt]?.lastErrorKey, "rate_limited")
        XCTAssertTrue(summary[yt]?.concurrencyReducedToOne ?? false)
        // once the deadline passes, the host is still tracked (strikes) but not "cooling"
        let later = limiter.displaySummary(now: t0.addingTimeInterval(31))
        XCTAssertTrue(later.isEmpty)
    }
}
