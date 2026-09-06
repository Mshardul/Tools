import Foundation

public enum CountdownFormat {
    public static func mmss(until: Date, now: Date) -> String {
        let remaining = max(0, Int(until.timeIntervalSince(now).rounded()))
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }
}
