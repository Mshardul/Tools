import Foundation
import GrabberKit

enum RowStatusText {
    static func text(
        for snapshot: JobSnapshot,
        maxAutoRetries _: Int,
        rate: HostRateDisplayState?,
        vpnActive: Bool = false
    ) -> String {
        switch snapshot.state {
        case .cooldown:
            "Cooling down"
        case .waitingForNetwork:
            "Waiting for network"
        case .queued:
            queued(snapshot, rate: rate)
        case .probing:
            "Resolving…"
        case .running:
            snapshot.progress.map { "Downloading \(Int($0.fraction * 100))%" } ?? "Downloading"
        case .paused:
            "Paused"
        case .completed:
            "Saved"
        case .cancelled:
            "Cancelled"
        case let .failed(errorClass):
            failedText(errorClass, vpnActive: vpnActive)
        }
    }

    private static func failedText(_ errorClass: ErrorClass, vpnActive: Bool) -> String {
        "Failed — \(sentence(for: errorClass, vpnActive: vpnActive))"
    }

    private static func sentence(for errorClass: ErrorClass, vpnActive: Bool) -> String {
        if case .botCheck = errorClass {
            return BotCheckCopy.sentence(vpnActive: vpnActive)
        }
        return errorClass.presentation.sentence
    }

    private static func queued(_ snapshot: JobSnapshot, rate: HostRateDisplayState?) -> String {
        if case .circuitOpen = rate?.state {
            return "Rate-limited — paused"
        }
        if case .cooldown = rate?.state {
            return "Cooling down"
        }
        if snapshot.attempt > 0, let until = snapshot.cooldownUntil, until > .now {
            return "Retrying"
        }
        return "Queued"
    }
}
