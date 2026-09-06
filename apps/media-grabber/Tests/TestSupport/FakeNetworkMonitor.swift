import Foundation
import GrabberKit

public final class FakeNetworkMonitor: NetworkPathMonitoring, @unchecked Sendable {
    private let box: LockedBox<Bool>
    private let continuation: AsyncStream<Bool>.Continuation
    public let stream: AsyncStream<Bool>

    public init(startOnline: Bool = true) {
        box = LockedBox(startOnline)
        (stream, continuation) = AsyncStream<Bool>.makeStream()
    }

    public var isOnline: Bool {
        get async { box.read { $0 } }
    }

    public func goOffline() {
        push(false)
    }

    public func goOnline() {
        push(true)
    }

    private func push(_ online: Bool) {
        box.mutate { $0 = online }
        continuation.yield(online)
    }
}
