import Foundation

public protocol MetadataTokenBucketing: Sendable {
    func acquire(onWait: (@Sendable (Date?) -> Void)?) async
}

public extension MetadataTokenBucketing {
    func acquire() async {
        await acquire(onWait: nil)
    }
}

public struct UnlimitedMetadataTokenBucket: MetadataTokenBucketing {
    public init() {}

    public func acquire(onWait: (@Sendable (Date?) -> Void)?) async {
        onWait?(nil)
    }
}

public actor MetadataTokenBucket: MetadataTokenBucketing {
    private let limit: Int
    private let window: TimeInterval
    private let clock: any Clock
    private var stamps: [Date] = []

    public init(limit: Int, windowSeconds: Int, clock: any Clock) {
        self.limit = max(1, limit)
        window = TimeInterval(windowSeconds)
        self.clock = clock
    }

    public func acquire(onWait: (@Sendable (Date?) -> Void)?) async {
        while true {
            if Task.isCancelled {
                onWait?(nil)
                return
            }

            let now = clock.now
            prune(now: now)

            if stamps.count < limit {
                stamps.append(now)
                onWait?(nil)
                return
            }

            guard let oldest = stamps.first else {
                continue
            }

            let next = oldest.addingTimeInterval(window)
            onWait?(next)
            await clock.sleep(until: next)

            if Task.isCancelled {
                onWait?(nil)
                return
            }
        }
    }

    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-window)
        stamps.removeAll { $0 <= cutoff }
    }
}
