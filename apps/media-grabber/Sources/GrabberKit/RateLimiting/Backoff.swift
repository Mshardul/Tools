import Foundation

// Exponential backoff with full jitter over a ladder + cap. The first caller of the
// deferred-start seam; an integer Retry-After wins over the ladder, still capped.
public enum Backoff {
    // attempt is 1-based — the first retry is attempt 1.
    public static func delay(
        attempt: Int,
        retryAfter: Int? = nil,
        tuning: EngineTuning = .default,
        jitter: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }
    ) -> TimeInterval {
        if let retryAfter, retryAfter > 0 {
            return TimeInterval(min(retryAfter, tuning.backoffCap))
        }
        let ladder = tuning.backoffLadder
        let index = min(max(attempt, 1), ladder.count) - 1
        let base = min(ladder[index], tuning.backoffCap)
        return jitter(0 ... Double(base))
    }
}
