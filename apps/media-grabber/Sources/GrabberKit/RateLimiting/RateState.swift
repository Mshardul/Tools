import Foundation

public enum RateState: Sendable, Equatable {
    case normal
    case cooldown(until: Date, strikes: Int)
    case circuitOpen(since: Date, strikes: Int)
}

public extension RateState {
    var strikes: Int {
        switch self {
        case .normal: 0
        case let .cooldown(_, strikes): strikes
        case let .circuitOpen(_, strikes): strikes
        }
    }
}

public struct HostRateDisplayState: Sendable, Equatable {
    public let state: RateState
    public let lastErrorKey: String?
    public let concurrencyReducedToOne: Bool

    public init(state: RateState, lastErrorKey: String?, concurrencyReducedToOne: Bool) {
        self.state = state
        self.lastErrorKey = lastErrorKey
        self.concurrencyReducedToOne = concurrencyReducedToOne
    }
}
