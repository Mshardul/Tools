import Foundation
import GrabberKit

enum BatchEligibility {
    private static let batchVerbs: Set<RowAction> = [
        .pause, .resume, .cancel, .forceStart, .retry, .remove
    ]

    static func offeredVerbs(snapshots: [JobSnapshot]) -> [RowAction] {
        RowAction.displayOrder.filter { verb in
            guard batchVerbs.contains(verb) else { return false }
            let ids = applicableIDs(verb: verb, snapshots: snapshots)
            if verb == .forceStart {
                return ids.count == 1
            }
            return !ids.isEmpty
        }
    }

    static func applicableIDs(verb: RowAction, snapshots: [JobSnapshot]) -> [UUID] {
        snapshots.compactMap { snap in
            snap.availableActions.contains(verb) ? snap.id : nil
        }
    }
}
