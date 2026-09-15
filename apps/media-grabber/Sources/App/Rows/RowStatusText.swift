import Foundation
import GrabberKit

enum RowStatusText {
    static func text(for snapshot: JobSnapshot) -> String {
        switch snapshot.state {
        case .queued: "Queued"
        case .probing: "Probing"
        case .running: "Downloading"
        case .paused: "Paused"
        case .waitingForNetwork: "Waiting for network"
        case .cooldown: "Cooling down"
        case .completed: "Saved"
        case .cancelled: "Cancelled"
        case .failed: "Failed"
        }
    }
}

enum RowRemarkText {
    static func text(
        for snapshot: JobSnapshot,
        queuePosition: Int?,
        rate: HostRateDisplayState?,
        vpnActive: Bool = false
    ) -> String {
        switch snapshot.state {
        case .queued:
            queued(snapshot, queuePosition: queuePosition, rate: rate)
        case .waitingForNetwork:
            "No connection"
        case let .cooldown(until):
            "Try again in " + CountdownFormat.mmss(until: until, now: .now)
        case let .failed(errorClass):
            sentence(for: errorClass, vpnActive: vpnActive)
        case .probing, .running, .paused, .completed, .cancelled:
            ""
        }
    }

    private static func queued(_ snapshot: JobSnapshot, queuePosition: Int?, rate: HostRateDisplayState?) -> String {
        if case .circuitOpen = rate?.state {
            return "Rate-limited"
        }
        if case let .cooldown(until, _) = rate?.state {
            return "Try again in " + CountdownFormat.mmss(until: until, now: .now)
        }
        if snapshot.attempt > 0, let until = snapshot.cooldownUntil, until > .now {
            return "Try again in " + CountdownFormat.mmss(until: until, now: .now)
        }
        if let queuePosition {
            return "#\(queuePosition)"
        }
        return ""
    }

    private static func sentence(for errorClass: ErrorClass, vpnActive: Bool) -> String {
        if case .botCheck = errorClass {
            return BotCheckCopy.sentence(vpnActive: vpnActive)
        }
        return errorClass.presentation.sentence
    }
}
