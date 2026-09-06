import Foundation

struct RateLimiter {
    private var states: [RateHost: RateState] = [:]
    private var lastErrorKey: [RateHost: String] = [:]
    private(set) var adaptiveCap: Int
    private var cleanStreak = 0
    private var strikeLoweredCap = false
    private var preferencesCap: Int
    private let tuning: EngineTuning

    init(tuning: EngineTuning, preferencesCap: Int) {
        self.tuning = tuning
        self.preferencesCap = max(1, preferencesCap)
        adaptiveCap = min(max(1, tuning.adaptiveConcurrencyStart), self.preferencesCap)
    }

    // MARK: Outcomes

    mutating func recordStrike(
        host: RateHost,
        retryAfter: Int?,
        lastErrorKey key: String,
        now: Date
    ) {
        states[host] = RatePolicy.next(
            state: states[host] ?? .normal,
            event: .strike(retryAfter: retryAfter),
            now: now,
            tuning: tuning
        )
        lastErrorKey[host] = key
        adaptiveCap = 1
        cleanStreak = 0
        strikeLoweredCap = true
    }

    mutating func recordCleanSuccess(host: RateHost, now: Date) {
        if let current = states[host] {
            let next = RatePolicy.next(
                state: current,
                event: .cleanSuccess,
                now: now,
                tuning: tuning
            )
            states[host] = next == .normal ? nil : next
            lastErrorKey[host] = nil
        }
        cleanStreak += 1
        if cleanStreak >= tuning.cleanStreakToRaise {
            adaptiveCap = min(adaptiveCap + 1, preferencesCap)
            cleanStreak = 0
            if adaptiveCap > 1 {
                strikeLoweredCap = false
            }
        }
    }

    // MARK: Queries

    func state(for host: RateHost) -> RateState {
        states[host] ?? .normal
    }

    func blocked(host: RateHost, now: Date) -> Bool {
        switch states[host] ?? .normal {
        case .normal: false
        case let .cooldown(until, _): until > now
        case .circuitOpen: true
        }
    }

    var circuitOpenHosts: Set<RateHost> {
        Set(states.compactMap { key, value in
            if case .circuitOpen = value {
                return key
            }
            return nil
        })
    }

    func cooldownDeadline(for host: RateHost) -> Date? {
        if case let .cooldown(until, _) = states[host] ?? .normal {
            return until
        }
        return nil
    }

    var concurrencyReducedByStrike: Bool {
        strikeLoweredCap && adaptiveCap == 1
    }

    func displaySummary(now: Date) -> [RateHost: HostRateDisplayState] {
        var out: [RateHost: HostRateDisplayState] = [:]
        for (host, state) in states where isVisible(state, now: now) {
            out[host] = HostRateDisplayState(
                state: state,
                lastErrorKey: lastErrorKey[host],
                concurrencyReducedToOne: concurrencyReducedByStrike
            )
        }
        return out
    }

    private func isVisible(_ state: RateState, now: Date) -> Bool {
        switch state {
        case .normal: false
        case let .cooldown(until, _): until > now
        case .circuitOpen: true
        }
    }

    // MARK: User actions

    mutating func resetCircuit(host: RateHost) {
        if case .circuitOpen = states[host] ?? .normal {
            states[host] = nil
            lastErrorKey[host] = nil
        }
    }

    mutating func resetAllCircuits() {
        for host in circuitOpenHosts {
            states[host] = nil
            lastErrorKey[host] = nil
        }
    }

    // MARK: Concurrency

    mutating func setPreferencesCap(_ cap: Int) {
        preferencesCap = max(1, cap)
        adaptiveCap = min(adaptiveCap, preferencesCap)
    }
}
