@testable import GrabberKit
import XCTest

final class EngineTuningRateLimitTests: XCTestCase {
    func testRateLimitTuningDefaults() {
        let tuning = EngineTuning.default
        XCTAssertEqual(tuning.circuitStrikeThreshold, 4)
        XCTAssertEqual(tuning.adaptiveConcurrencyStart, 2)
        XCTAssertEqual(tuning.cleanStreakToRaise, 5)
        XCTAssertEqual(tuning.networkOfflineGraceSeconds, 2)
        XCTAssertEqual(tuning.networkOnlineSettleSeconds, 2)
        XCTAssertEqual(tuning.concurrentFragmentsNormal, 4)
        XCTAssertEqual(tuning.concurrentFragmentsThrottled, 1)
    }

    func testRateLimitEnvOverrides() {
        let env = [
            "MG_CIRCUIT_STRIKE_THRESHOLD": "2",
            "MG_ADAPTIVE_CONCURRENCY_START": "1",
            "MG_CLEAN_STREAK_TO_RAISE": "3",
            "MG_NETWORK_OFFLINE_GRACE_SECONDS": "5",
            "MG_NETWORK_ONLINE_SETTLE_SECONDS": "4",
            "MG_CONCURRENT_FRAGMENTS_NORMAL": "6",
            "MG_CONCURRENT_FRAGMENTS_THROTTLED": "2"
        ]
        let tuning = EngineTuning.resolved(environment: env)
        XCTAssertEqual(tuning.circuitStrikeThreshold, 2)
        XCTAssertEqual(tuning.adaptiveConcurrencyStart, 1)
        XCTAssertEqual(tuning.cleanStreakToRaise, 3)
        XCTAssertEqual(tuning.networkOfflineGraceSeconds, 5)
        XCTAssertEqual(tuning.networkOnlineSettleSeconds, 4)
        XCTAssertEqual(tuning.concurrentFragmentsNormal, 6)
        XCTAssertEqual(tuning.concurrentFragmentsThrottled, 2)
    }

    func testMalformedEnvKeepsDefault() {
        let tuning = EngineTuning.resolved(environment: ["MG_CIRCUIT_STRIKE_THRESHOLD": "nope"])
        XCTAssertEqual(tuning.circuitStrikeThreshold, 4)
    }
}
