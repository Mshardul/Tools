import Foundation

public protocol Clock: Sendable {
    var now: Date { get }
    func sleep(until deadline: Date) async
}

public struct SystemClock: Clock {
    public init() {}

    public var now: Date {
        Date()
    }

    public func sleep(until deadline: Date) async {
        let interval = deadline.timeIntervalSinceNow
        guard interval > 0 else { return }
        try? await Task.sleep(for: .seconds(interval))
    }
}
