@testable import TestSupport
import XCTest

final class FakeClockTests: XCTestCase {
    func test_advancePastDeadline_wakesSleeper() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let woke = LockedBox(false)
        let sleeper = Task {
            await clock.sleep(until: Date(timeIntervalSince1970: 10))
            woke.mutate { $0 = true }
        }
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(woke.read { $0 })
        clock.advance(by: .seconds(10))
        await sleeper.value
        XCTAssertTrue(woke.read { $0 })
    }

    func test_fixtureLoadsCheckedInCorpus() {
        XCTAssertTrue(Fixture.text("ytdlp-J-video.json").contains("\"title\""))
    }
}
