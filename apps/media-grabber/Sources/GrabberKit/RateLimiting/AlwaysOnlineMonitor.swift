import Foundation

public struct AlwaysOnlineMonitor: NetworkPathMonitoring {
    public init() {}

    public var isOnline: Bool {
        get async { true }
    }

    public var stream: AsyncStream<Bool> {
        AsyncStream { $0.finish() } // never yields
    }
}
