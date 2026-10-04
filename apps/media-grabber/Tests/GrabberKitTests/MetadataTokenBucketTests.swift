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

    func testAcquireReportsWaitDeadlineThenClears() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1000))
        let bucket = MetadataTokenBucket(limit: 1, windowSeconds: 60, clock: clock)
        await bucket.acquire(onWait: nil)

        let reported = LockedBox<[Date?]>([])
        let waiter = Task {
            await bucket.acquire { until in
                reported.mutate { $0.append(until) }
            }
        }
        await Task.yield()
        await Task.yield()

        let mid = reported.read { $0 }
        XCTAssertTrue(mid.contains { $0 != nil })
        XCTAssertEqual(mid.compactMap(\.self).last, Date(timeIntervalSince1970: 1060))

        clock.advance(by: .seconds(60))
        await waiter.value
        XCTAssertEqual(reported.read { $0.last! }, nil)
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
