import Foundation
@testable import GrabberKit
@testable import TestSupport
import XCTest

final class MetadataTokenBucketTests: XCTestCase {
    func testThirdAcquireIsImmediateFourthWaitsUntilWindowRolls() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let bucket = MetadataTokenBucket(limit: 3, windowSeconds: 60, clock: clock)
        await bucket.acquire()
        await bucket.acquire()
        await bucket.acquire()

        let fourth = Task { await bucket.acquire() }
        await Task.yield()
        XCTAssertFalse(fourth.isCancelled)

        let finished = LockedBox(false)
        Task {
            _ = await fourth.value
            finished.mutate { $0 = true }
        }
        await Task.yield()
        XCTAssertFalse(finished.read { $0 })

        clock.advance(by: .seconds(60))
        _ = await fourth.value
        await Task.yield()
        XCTAssertTrue(finished.read { $0 })
    }

    func testCancelledAcquireDoesNotStealToken() async {
        let clock = CancellableClock(now: Date(timeIntervalSince1970: 0))
        let bucket = MetadataTokenBucket(limit: 3, windowSeconds: 60, clock: clock)
        await bucket.acquire()
        await bucket.acquire()
        await bucket.acquire()

        let cancelled = Task { await bucket.acquire() }
        await Task.yield()
        cancelled.cancel()
        _ = await cancelled.value

        let finished = LockedBox(false)
        let following = Task {
            await bucket.acquire()
            finished.mutate { $0 = true }
        }
        await Task.yield()
        XCTAssertFalse(finished.read { $0 })

        clock.advance(by: .seconds(60))
        _ = await following.value
        XCTAssertTrue(finished.read { $0 })
    }
}

private final class CancellableClock: Clock, @unchecked Sendable {
    private let nowBox: LockedBox<Date>

    init(now: Date) {
        nowBox = LockedBox(now)
    }

    var now: Date {
        nowBox.read { $0 }
    }

    func advance(by duration: Duration) {
        nowBox.mutate { $0 += TimeInterval(duration.components.seconds) }
    }

    func sleep(until deadline: Date) async {
        while !Task.isCancelled, now < deadline {
            await Task.yield()
        }
    }
}
