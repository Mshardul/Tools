import Foundation
import GrabberKit

@MainActor
extension RowStore {
    func activeSpeed(_ snapshots: [JobSnapshot]) -> Double {
        snapshots.reduce(0) { total, snapshot in
            guard snapshot.state == .running else { return total }
            return total + (snapshot.progress?.speedBytesPerSec ?? 0)
        }
    }

    func activeEta(_ snapshots: [JobSnapshot]) -> Int? {
        let values = snapshots.compactMap { snapshot -> Int? in
            guard snapshot.state == .running else { return nil }
            return snapshot.progress?.etaSeconds
        }
        return values.max()
    }

    func sumKnown<T: AdditiveArithmetic>(_ values: [T]) -> T? {
        guard !values.isEmpty else { return nil }
        return values.reduce(.zero) { $0 + $1 }
    }

    func groupFinishedAt(_ snapshots: [JobSnapshot]) -> Date? {
        guard !snapshots.isEmpty, snapshots.allSatisfy({ $0.state == .completed }) else {
            return nil
        }
        return snapshots.compactMap(\.finishedAt).max()
    }

    func common(_ values: [String]) -> String {
        guard let first = values.first else { return "—" }
        return values.allSatisfy { $0 == first } ? first : "mixed"
    }

    func statusText(total: Int, completed: Int, failed: Int) -> String {
        "\(completed) done · \(failed) failed · \(total - completed - failed) queued"
    }

    func isFailed(_ state: JobState) -> Bool {
        if case .failed = state {
            return true
        }
        return false
    }

    func isCancellable(_ state: JobState) -> Bool {
        switch state {
        case .queued, .paused, .probing, .running, .cooldown, .waitingForNetwork:
            true
        default:
            false
        }
    }
}
