import Foundation

public protocol MetadataTokenBucketing: Sendable {
    func acquire() async
}

public struct UnlimitedMetadataTokenBucket: MetadataTokenBucketing {
    public init() {}

    public func acquire() async {}
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

    public func acquire() async {
        while true {
            if Task.isCancelled {
                return
            }

            let now = clock.now
            prune(now: now)

            if stamps.count < limit {
                stamps.append(now)
                return
            }

            guard let oldest = stamps.first else {
                continue
            }

            await clock.sleep(until: oldest.addingTimeInterval(window))

            if Task.isCancelled {
                return
            }
        }
    }

    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-window)
        stamps.removeAll { $0 <= cutoff }
    }
}
