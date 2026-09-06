@testable import GrabberKit
import TestSupport
import XCTest

final class NetworkPathMonitorTests: XCTestCase {
    func testFakeEmitsTransitions() async {
        let fake = FakeNetworkMonitor(startOnline: true)
        let received = LockedBox<[Bool]>([])
        let task = Task {
            for await value in fake.stream {
                let count = received.mutate { list -> Int in
                    list.append(value)
                    return list.count
                }
                if count == 2 {
                    break
                }
            }
        }
        // give the consumer a tick to attach before pushing
        try? await Task.sleep(for: .milliseconds(20))
        fake.goOffline()
        fake.goOnline()
        await task.value
        XCTAssertEqual(received.read { $0 }, [false, true])
    }

    func testLiveImplDebouncesOfflineByGrace() async {
        let sleeps = LockedBox<[TimeInterval]>([])
        let monitor = NWPathNetworkMonitor(
            offlineGrace: 2, onlineSettle: 2,
            sleep: { duration in sleeps.mutate { $0.append(duration) } }
        )
        let received = LockedBox<[Bool]>([])
        let task = Task {
            for await value in monitor.stream {
                received.mutate { $0.append(value) }
                break
            }
        }
        try? await Task.sleep(for: .milliseconds(20))
        monitor.pushRawPathForTesting(satisfied: false)
        await task.value
        XCTAssertEqual(received.read { $0 }, [false])
        XCTAssertTrue(sleeps.read { $0 }.contains(2))
    }
}
