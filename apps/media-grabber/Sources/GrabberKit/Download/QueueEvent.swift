import Foundation

public struct QueueSnapshot: Sendable, Equatable {
    public let jobs: [JobSnapshot]
    public let revision: UInt64
    public let queueHalt: QueueHaltReason?
    public let generatedAt: Date
    public let hostRateSummary: [RateHost: HostRateDisplayState]
    public let isOnline: Bool

    public init(
        jobs: [JobSnapshot],
        revision: UInt64,
        queueHalt: QueueHaltReason?,
        generatedAt: Date,
        hostRateSummary: [RateHost: HostRateDisplayState],
        isOnline: Bool
    ) {
        self.jobs = jobs
        self.revision = revision
        self.queueHalt = queueHalt
        self.generatedAt = generatedAt
        self.hostRateSummary = hostRateSummary
        self.isOnline = isOnline
    }
}

public enum QueueEvent: Sendable {
    case snapshot(QueueSnapshot)
    case progress([UUID: Progress], revision: UInt64)
}
