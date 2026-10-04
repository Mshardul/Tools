import Foundation

struct RateLimiter {
    private struct HostConcurrency {
        var adaptiveCap: Int
        var cleanStreak: Int = 0
        var strikeLoweredCap: Bool = false
    }

    private var states: [RateHost: RateState] = [:]
    private var lastErrorKey: [RateHost: String] = [:]
    private var concurrency: [RateHost: HostConcurrency] = [:]
    private var preferencesCap: Int
    private let tuning: EngineTuning

    init(tuning: EngineTuning, preferencesCap: Int) {
        self.tuning = tuning
        self.preferencesCap = max(1, preferencesCap)
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
        var entry = concurrencyEntry(for: host)
        entry.adaptiveCap = 1
        entry.cleanStreak = 0
        entry.strikeLoweredCap = true
        concurrency[host] = entry
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
        var entry = concurrencyEntry(for: host)
        entry.cleanStreak += 1
        if entry.cleanStreak >= tuning.cleanStreakToRaise {
            entry.adaptiveCap = min(entry.adaptiveCap + 1, preferencesCap)
            entry.cleanStreak = 0
            if entry.adaptiveCap > 1 {
                entry.strikeLoweredCap = false
            }
        }
        concurrency[host] = entry
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

    func adaptiveCap(for host: RateHost) -> Int {
        concurrency[host]?.adaptiveCap ?? startCap
    }

    func concurrencyReducedToOne(for host: RateHost) -> Bool {
        guard let entry = concurrency[host] else { return false }
        return entry.strikeLoweredCap && entry.adaptiveCap == 1
    }

    func displaySummary(now: Date) -> [RateHost: HostRateDisplayState] {
        var out: [RateHost: HostRateDisplayState] = [:]
        for (host, state) in states where isVisible(state, now: now) {
            out[host] = HostRateDisplayState(
                state: state,
                lastErrorKey: lastErrorKey[host],
                concurrencyReducedToOne: concurrencyReducedToOne(for: host)
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

    private var startCap: Int {
        min(max(1, tuning.adaptiveConcurrencyStart), preferencesCap)
    }

    private func concurrencyEntry(for host: RateHost) -> HostConcurrency {
        concurrency[host] ?? HostConcurrency(adaptiveCap: startCap)
    }

    // MARK: User actions

    mutating func resetCircuit(host: RateHost, now: Date) {
        guard case .circuitOpen = states[host] ?? .normal else { return }
        let next = RatePolicy.next(
            state: states[host] ?? .normal,
            event: .userReset,
            now: now,
            tuning: tuning
        )
        states[host] = next == .normal ? nil : next
        lastErrorKey[host] = nil
    }

    mutating func resetAllCircuits(now: Date) {
        for host in circuitOpenHosts {
            resetCircuit(host: host, now: now)
        }
    }

    // MARK: Concurrency

    mutating func setPreferencesCap(_ cap: Int) {
        preferencesCap = max(1, cap)
        for (host, var entry) in concurrency {
            entry.adaptiveCap = min(entry.adaptiveCap, preferencesCap)
            concurrency[host] = entry
        }
    }
}
