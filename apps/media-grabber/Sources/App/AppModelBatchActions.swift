import Foundation
import GrabberKit

extension AppModel {
    func clearTableSelection() {
        rowStore.clearSelection()
    }

    func handleBatchAction(_ action: RowAction) async {
        let selected = selectedSnapshots()
        let ids = BatchEligibility.applicableIDs(verb: action, snapshots: selected)
        guard !ids.isEmpty else { return }

        switch action {
        case .remove:
            await batchRemove(ids: ids, snapshots: selected)
        case .forceStart:
            guard ids.count == 1, let id = ids.first else { return }
            await confirmedForceStart(id)
        case .cancel:
            await batchCancel(ids: ids)
        case .pause, .resume, .retry:
            for id in ids {
                await handleRowAction(id, action: action)
            }
        case .reveal, .openInBrowser, .showLog, .retryWithCookies:
            break
        }
    }

    private func selectedSnapshots() -> [JobSnapshot] {
        let selected = rowStore.selectedJobIDs
        return rowStore.rows.compactMap { row in
            selected.contains(row.id) ? row.snapshot : nil
        }
    }

    private func batchRemove(ids: [UUID], snapshots: [JobSnapshot]) async {
        let targets = snapshots.filter { ids.contains($0.id) }
        if targets.contains(where: needsRemoveConfirm) {
            let confirmed = await confirm(AppModelDialogs.removeConfirmation())
            guard confirmed else { return }
        }
        for id in ids {
            await removeRow(id)
        }
    }

    private func batchCancel(ids: [UUID]) async {
        let confirmed = await confirm(AppModelDialogs.batchCancelConfirmation())
        guard confirmed else { return }
        for id in ids {
            await engine.cancel(id)
        }
    }
}
