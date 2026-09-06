import Foundation

public enum RatePolicyEvent: Sendable, Equatable {
    case strike(retryAfter: Int?)
    case cleanSuccess
    case userReset
}

public enum RatePolicy {
    public static func next(
        state: RateState,
        event: RatePolicyEvent,
        now: Date,
        tuning: EngineTuning,
        jitter: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }
    ) -> RateState {
        switch event {
        case .cleanSuccess, .userReset:
            .normal
        case let .strike(retryAfter):
            afterStrike(
                state,
                retryAfter: retryAfter,
                now: now,
                tuning: tuning,
                jitter: jitter
            )
        }
    }

    private static func afterStrike(
        _ state: RateState,
        retryAfter: Int?,
        now: Date,
        tuning: EngineTuning,
        jitter: (ClosedRange<Double>) -> Double
    ) -> RateState {
        if case let .cooldown(until, _) = state, until > now {
            return state
        }
        let strikes = state.strikes + 1
        if strikes >= tuning.circuitStrikeThreshold {
            return .circuitOpen(since: now, strikes: strikes)
        }
        let delay = Backoff.delay(
            attempt: strikes,
            retryAfter: retryAfter,
            tuning: tuning,
            jitter: jitter
        )
        return .cooldown(until: now.addingTimeInterval(delay), strikes: strikes)
    }
}
