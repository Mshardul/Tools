import Foundation
import GrabberKit

public final class FakeClock: Clock, @unchecked Sendable {
    private struct State {
        var now: Date
        var waiters: [(deadline: Date, resume: () -> Void)] = []
    }

    private let box: LockedBox<State>

    public init(now: Date = Date(timeIntervalSince1970: 0)) {
        box = LockedBox(State(now: now))
    }

    public var now: Date {
        box.read { $0.now }
    }

    public func advance(by duration: Duration) {
        let fired: [() -> Void] = box.mutate { state in
            state.now += TimeInterval(duration.components.seconds)
            let due = state.waiters.filter { $0.deadline <= state.now }
            state.waiters.removeAll { $0.deadline <= state.now }
            return due.map(\.resume)
        }
        fired.forEach { $0() }
    }

    public func sleep(until deadline: Date) async {
        if box.read({ $0.now >= deadline }) {
            return
        }
        await withCheckedContinuation { cont in
            let alreadyDue = box.mutate { state -> Bool in
                if state.now >= deadline {
                    return true
                }
                state.waiters.append((deadline, { cont.resume() }))
                return false
            }
            if alreadyDue {
                cont.resume()
            }
        }
    }
}
