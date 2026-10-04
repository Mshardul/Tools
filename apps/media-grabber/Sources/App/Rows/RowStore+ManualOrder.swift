import Foundation
import GrabberKit

@MainActor
extension RowStore {
    func clearManualOrder() {
        guard manualOrder != nil else { return }
        manualOrder = nil
        recomputeVisible()
    }

    func setManualOrder(_ ids: [UUID]) {
        manualOrder = ids
        recomputeVisible()
    }

    @discardableResult
    func moveVisibleItem(from fromIndex: Int, to toIndex: Int) -> Bool {
        guard visibleItems.indices.contains(fromIndex) else { return false }
        guard case let .child(source) = visibleItems[fromIndex] else { return false }
        let sourceGroup = source.snapshot.playlistGroupID

        if let sourceGroup {
            guard let destChild = destinationChild(at: toIndex),
                  destChild.snapshot.playlistGroupID == sourceGroup
            else { return false }
        } else if toIndex < visibleItems.count {
            switch visibleItems[toIndex] {
            case .header:
                break
            case let .child(dest):
                if dest.snapshot.playlistGroupID != nil {
                    return false
                }
            }
        }

        let scopeIDs = scopedVisibleChildIDs(for: source)
        guard let fromScope = scopeIDs.firstIndex(of: source.id) else { return false }
        let toScope = scopedDestinationIndex(
            toIndex: toIndex,
            sourceID: source.id,
            scopeIDs: scopeIDs,
            sourceGroup: sourceGroup
        )
        var reordered = scopeIDs
        reordered.remove(at: fromScope)
        let insertAt = fromScope < toScope ? toScope - 1 : toScope
        reordered.insert(source.id, at: min(insertAt, reordered.count))
        manualOrder = spliceManualOrder(reorderedScope: reordered)
        recomputeVisible()
        return true
    }

    func reconcileManualOrderWithRows() {
        guard var order = manualOrder else { return }
        let live = Set(rows.map(\.id))
        order.removeAll { !live.contains($0) }
        let known = Set(order)
        for id in rows.map(\.id) where !known.contains(id) {
            order.append(id)
        }
        manualOrder = order.isEmpty ? nil : order
    }

    private func destinationChild(at index: Int) -> RowModel? {
        guard visibleItems.indices.contains(index) else { return nil }
        if case let .child(row) = visibleItems[index] {
            return row
        }
        return nil
    }

    private func scopedVisibleChildIDs(for source: RowModel) -> [UUID] {
        if let groupID = source.snapshot.playlistGroupID {
            return visibleItems.compactMap { item in
                guard case let .child(row) = item else { return nil }
                return row.snapshot.playlistGroupID == groupID ? row.id : nil
            }
        }
        return visibleItems.compactMap { item in
            guard case let .child(row) = item else { return nil }
            return row.snapshot.playlistGroupID == nil ? row.id : nil
        }
    }

    private func scopedDestinationIndex(
        toIndex: Int,
        sourceID: UUID,
        scopeIDs: [UUID],
        sourceGroup: UUID?
    ) -> Int {
        if toIndex >= visibleItems.count {
            return scopeIDs.count
        }
        if sourceGroup == nil, case .header = visibleItems[toIndex] {
            return scopeIDs.count
        }
        guard case let .child(dest) = visibleItems[toIndex] else {
            return scopeIDs.count
        }
        if dest.id == sourceID {
            return scopeIDs.firstIndex(of: sourceID) ?? scopeIDs.count
        }
        return scopeIDs.firstIndex(of: dest.id) ?? scopeIDs.count
    }

    private func spliceManualOrder(reorderedScope: [UUID]) -> [UUID] {
        let base = manualOrder ?? rows.map(\.id)
        let scopeSet = Set(reorderedScope)
        var result: [UUID] = []
        var scopeIterator = reorderedScope.makeIterator()
        var inserted = Set<UUID>()
        for id in base {
            if scopeSet.contains(id) {
                if let next = scopeIterator.next() {
                    result.append(next)
                    inserted.insert(next)
                }
            } else {
                result.append(id)
            }
        }
        for id in reorderedScope where !inserted.contains(id) {
            result.append(id)
        }
        return result
    }
}
