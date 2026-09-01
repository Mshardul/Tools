@testable import GrabberKit
import XCTest

final class EngineTuningTests: XCTestCase {
    func test_noEnvKeysGivesDefault() {
        XCTAssertEqual(EngineTuning.resolved(environment: [:]), .default)
    }

    func test_eachYtDlpKeyParses() {
        let env = [
            "MG_YTDLP_RETRIES": "7",
            "MG_YTDLP_FRAGMENT_RETRIES": "20",
            "MG_YTDLP_SOCKET_TIMEOUT": "45",
            "MG_YTDLP_RETRY_SLEEP": "exp=1:20",
            "MG_YTDLP_THROTTLED_RATE_KBPS": "50",
            "MG_YTDLP_FILE_ACCESS_RETRIES": "9",
            "MG_YTDLP_SLEEP_REQUESTS": "2",
            "MG_YTDLP_SLEEP_INTERVAL": "3",
            "MG_YTDLP_MAX_SLEEP_INTERVAL": "8"
        ]
        let tuning = EngineTuning.resolved(environment: env).ytDlp
        XCTAssertEqual(tuning.retries, 7)
        XCTAssertEqual(tuning.fragmentRetries, 20)
        XCTAssertEqual(tuning.socketTimeout, 45)
        XCTAssertEqual(tuning.retrySleep, "exp=1:20")
        XCTAssertEqual(tuning.throttledRateKBps, 50)
        XCTAssertEqual(tuning.fileAccessRetries, 9)
        XCTAssertEqual(tuning.sleepRequests, 2)
        XCTAssertEqual(tuning.sleepInterval, 3)
        XCTAssertEqual(tuning.maxSleepInterval, 8)
    }

    func test_malformedIntKeepsDefaultForThatField() {
        let tuning = EngineTuning.resolved(environment: ["MG_YTDLP_RETRIES": "not-a-number"]).ytDlp
        XCTAssertEqual(tuning.retries, YtDlpTuning.default.retries)
    }

    func test_backoffLadderParsesCommaList() {
        let resolved = EngineTuning.resolved(environment: ["MG_BACKOFF_LADDER": "10,20,30"])
        XCTAssertEqual(resolved.backoffLadder, [10, 20, 30])
    }

    func test_backoffCapParses() {
        XCTAssertEqual(
            EngineTuning.resolved(environment: ["MG_BACKOFF_CAP": "120"]).backoffCap,
            120
        )
    }

    func test_malformedLadderKeepsDefault() {
        XCTAssertEqual(
            EngineTuning.resolved(environment: ["MG_BACKOFF_LADDER": "10,x,30"]).backoffLadder,
            EngineTuning.default.backoffLadder
        )
    }
}
