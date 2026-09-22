import Foundation

@MainActor
extension RowStore {
    func visibleChildIDs() -> Set<UUID> {
        Set(visibleChildOrder())
    }

    func visibleChildOrder() -> [UUID] {
        visibleItems.compactMap { item in
            guard case let .child(row) = item else { return nil }
            return row.id
        }
    }

    func setSelectedJobIDs(_ ids: Set<UUID>, anchor: UUID?) {
        selectedJobIDs = RowSelection.prune(ids, visibleChildIDs: visibleChildIDs())
        if let anchor, selectedJobIDs.contains(anchor) {
            selectionAnchorID = anchor
        } else if let current = selectionAnchorID, !selectedJobIDs.contains(current) {
            selectionAnchorID = nil
        }
    }

    func clearSelection() {
        selectedJobIDs = []
        selectionAnchorID = nil
    }

    func selectAllVisibleChildren() {
        let order = visibleChildOrder()
        selectedJobIDs = Set(order)
        selectionAnchorID = order.first
    }

    func pruneSelectionToVisible() {
        selectedJobIDs = RowSelection.prune(selectedJobIDs, visibleChildIDs: visibleChildIDs())
        if let anchor = selectionAnchorID, !selectedJobIDs.contains(anchor) {
            selectionAnchorID = nil
        }
    }
}
