import Foundation

enum RowSelection {
    static func prune(_ selected: Set<UUID>, visibleChildIDs: Set<UUID>) -> Set<UUID> {
        selected.intersection(visibleChildIDs)
    }

    static func toggle(_ id: UUID, in selected: Set<UUID>) -> Set<UUID> {
        var next = selected
        if next.contains(id) {
            next.remove(id)
        } else {
            next.insert(id)
        }
        return next
    }

    // Shift-click replaces selection with the inclusive visible-child slice.
    static func rangeSelecting(
        from anchor: UUID?,
        to target: UUID,
        visibleChildOrder: [UUID],
        replacing _: Set<UUID>
    ) -> Set<UUID> {
        guard let anchor,
              let fromIndex = visibleChildOrder.firstIndex(of: anchor),
              let toIndex = visibleChildOrder.firstIndex(of: target)
        else {
            return [target]
        }
        let lo = min(fromIndex, toIndex)
        let hi = max(fromIndex, toIndex)
        return Set(visibleChildOrder[lo ... hi])
    }
}
