import Foundation
import GrabberKit

private enum VisibleBlock {
    case single(RowModel, originalIndex: Int)
    case group(GroupBlock)
}

private struct GroupBlock {
    let group: PlaylistGroup
    let allChildren: [RowModel]
    let visibleChildren: [RowModel]
    let originalIndex: Int
}

private struct GroupEntry {
    let id: UUID
    let row: RowModel
    let index: Int
}

private enum BlockSortValue: Comparable {
    case number(Double)
    case string(String)
}

@MainActor
extension RowStore {
    func applyGroups(_ groups: [PersistedPlaylistGroup]) {
        groupRegistry = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        recomputeVisible()
    }

    func setCollapsed(id: UUID, _ isCollapsed: Bool) {
        localCollapsed[id] = isCollapsed
        recomputeVisible()
    }

    func recomputeVisibleItems(filtered: [RowModel]) {
        let filteredIDs = Set(filtered.map(\.id))
        let blocks = makeVisibleBlocks(filteredIDs: filteredIDs)
        let orderedBlocks = sorted(blocks)
        let items = orderedBlocks.flatMap { visibleItems(for: $0) }
        let nextGroups = orderedBlocks.compactMap { block -> PlaylistGroup? in
            guard case let .group(groupBlock) = block else { return nil }
            return groupBlock.group
        }

        visibleItems = items
        if groups != nextGroups {
            groups = nextGroups
        }
    }

    private func makeVisibleBlocks(filteredIDs: Set<UUID>) -> [VisibleBlock] {
        let grouped = Dictionary(grouping: rows.enumerated().compactMap(groupedRow)) { $0.id }
        let groupedIDs = Set(grouped.keys)
        var blocks = ungroupedBlocks(groupedIDs: groupedIDs, filteredIDs: filteredIDs)

        for (id, entries) in grouped {
            let allChildren = entries.map(\.row)
            let visibleChildren = allChildren.filter { filteredIDs.contains($0.id) }
            guard !visibleChildren.isEmpty else { continue }
            blocks.append(.group(makeGroupBlock(id: id, entries: entries, visible: visibleChildren)))
        }
        return blocks
    }

    private func groupedRow(
        _ entry: EnumeratedSequence<[RowModel]>.Element
    ) -> GroupEntry? {
        guard let id = entry.element.snapshot.playlistGroupID else { return nil }
        return GroupEntry(id: id, row: entry.element, index: entry.offset)
    }

    private func ungroupedBlocks(
        groupedIDs: Set<UUID>,
        filteredIDs: Set<UUID>
    ) -> [VisibleBlock] {
        rows.enumerated().compactMap { index, row in
            guard isUngrouped(row, groupedIDs: groupedIDs) else { return nil }
            guard filteredIDs.contains(row.id) else { return nil }
            return .single(row, originalIndex: index)
        }
    }

    private func isUngrouped(_ row: RowModel, groupedIDs: Set<UUID>) -> Bool {
        guard let id = row.snapshot.playlistGroupID else { return true }
        return !groupedIDs.contains(id)
    }

    private func makeGroupBlock(
        id: UUID,
        entries: [GroupEntry],
        visible: [RowModel]
    ) -> GroupBlock {
        let allChildren = entries.map(\.row)
        let registry = groupRegistry[id]
        let group = makePlaylistGroup(id: id, registry: registry, children: allChildren)
        return GroupBlock(
            group: group,
            allChildren: allChildren,
            visibleChildren: visible.sorted(by: playlistIndexSort),
            originalIndex: entries.map(\.index).min() ?? 0
        )
    }

    private func makePlaylistGroup(
        id: UUID,
        registry: PersistedPlaylistGroup?,
        children: [RowModel]
    ) -> PlaylistGroup {
        let snapshots = children.map(\.snapshot)
        let completed = snapshots.filter { $0.state == .completed }.count
        let failed = snapshots.filter { isFailed($0.state) }.count
        let running = snapshots.filter { $0.state == .running }.count
        let cancellable = snapshots.filter { isCancellable($0.state) }.count
        return PlaylistGroup(
            id: id,
            title: groupTitle(registry: registry, children: snapshots),
            totalCount: children.count,
            completedCount: completed,
            failedCount: failed,
            runningCount: running,
            cancellableCount: cancellable,
            rollupFraction: rollupFraction(snapshots),
            speedBytesPerSec: activeSpeed(snapshots),
            etaSeconds: activeEta(snapshots),
            sizeBytes: sumKnown(snapshots.compactMap(\.sizeBytes)),
            durationSeconds: sumKnown(snapshots.compactMap(\.durationSeconds)),
            addedAt: snapshots.map(\.addedAt).min() ?? Date(timeIntervalSince1970: 0),
            finishedAt: groupFinishedAt(snapshots),
            siteLabel: common(children.map(\.siteLabel)),
            typeLabel: common(children.map(\.typeLabel)),
            qualityLabel: common(children.map(\.qualityLabel)),
            destinationLabel: common(snapshots.map(\.destFolder.path)),
            clientUsedLabel: common(snapshots.map { $0.playerClientUsed ?? "—" }),
            attempt: snapshots.map(\.attempt).max() ?? 0,
            statusText: statusText(total: children.count, completed: completed, failed: failed),
            isCollapsed: localCollapsed[id] ?? registry?.isCollapsed ?? false
        )
    }

    private func sorted(_ blocks: [VisibleBlock]) -> [VisibleBlock] {
        guard let column = activeSortColumn else {
            return blocks.sorted { originalIndex($0) < originalIndex($1) }
        }
        return blocks.sorted { lhs, rhs in
            compare(lhs, rhs, column: column)
        }
    }

    private func compare(_ lhs: VisibleBlock, _ rhs: VisibleBlock, column: ColumnID) -> Bool {
        let left = sortValue(lhs, column: column)
        let right = sortValue(rhs, column: column)
        switch (left, right) {
        case let (leftValue?, rightValue?):
            return activeSortAscending ? leftValue < rightValue : leftValue > rightValue
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        case (nil, nil):
            return originalIndex(lhs) < originalIndex(rhs)
        }
    }

    private func sortValue(_ block: VisibleBlock, column: ColumnID) -> BlockSortValue? {
        switch block {
        case let .single(row, _):
            rowSortValue(row, column: column)
        case let .group(block):
            groupSortValue(block, column: column)
        }
    }

    private func visibleItems(for block: VisibleBlock) -> [VisibleItem] {
        switch block {
        case let .single(row, _):
            return [VisibleItem.child(row)]
        case let .group(block):
            var items: [VisibleItem] = [.header(block.group)]
            if !block.group.isCollapsed {
                items.append(contentsOf: block.visibleChildren.map { VisibleItem.child($0) })
            }
            return items
        }
    }

    private func rowSortValue(_ row: RowModel, column: ColumnID) -> BlockSortValue? {
        if let key = sortKey(row, column: column) {
            return .number(key)
        }
        return switch column {
        case .title: .string(row.snapshot.title ?? "")
        case .status: .string(row.statusText)
        case .type: .string(row.typeLabel)
        case .quality: .string(row.qualityLabel)
        case .site: .string(row.siteLabel)
        case .destination: .string(row.snapshot.destFolder.path)
        case .clientUsed: .string(row.snapshot.playerClientUsed ?? "—")
        default: nil
        }
    }

    func sortKey(_ row: RowModel, column: ColumnID) -> Double? {
        switch column {
        case .progress: row.snapshot.progress?.fraction
        case .speed: row.snapshot.progress?.speedBytesPerSec
        case .eta: row.snapshot.progress?.etaSeconds.map(Double.init)
        case .size: row.snapshot.sizeBytes.map(Double.init)
        case .addedAt: row.snapshot.addedAt.timeIntervalSince1970
        case .finishedAt: row.snapshot.finishedAt?.timeIntervalSince1970
        case .duration: row.snapshot.durationSeconds.map(Double.init)
        case .attempt: Double(row.snapshot.attempt)
        default: nil
        }
    }

    var activeSortColumn: ColumnID? {
        columnConfig.sortColumn
    }

    var activeSortAscending: Bool {
        columnConfig.sortDirection != .descending
    }

    static func progressBucket(for snapshot: JobSnapshot) -> Int {
        guard snapshot.state != .completed, let fraction = snapshot.progress?.fraction else {
            return snapshot.state == .completed ? 10 : 0
        }
        return max(0, min(10, Int(fraction * 10)))
    }

    private func groupSortValue(_ block: GroupBlock, column: ColumnID) -> BlockSortValue? {
        if let number = groupNumericSortValue(block, column: column) {
            return .number(number)
        }
        if let string = groupStringSortValue(block.group, column: column) {
            return .string(string)
        }
        return nil
    }

    private func groupNumericSortValue(_ block: GroupBlock, column: ColumnID) -> Double? {
        switch column {
        case .progress: block.group.rollupFraction
        case .speed: block.group.speedBytesPerSec
        case .eta: block.group.etaSeconds.map(Double.init)
        case .size: block.group.sizeBytes.map(Double.init)
        case .addedAt: groupBlockAddedAt(block)
        case .finishedAt: block.group.finishedAt?.timeIntervalSince1970
        case .duration: block.group.durationSeconds.map(Double.init)
        case .attempt: Double(block.group.attempt)
        default: nil
        }
    }

    private func groupStringSortValue(_ group: PlaylistGroup, column: ColumnID) -> String? {
        switch column {
        case .title: group.title
        case .status: group.statusText
        case .type: group.typeLabel
        case .quality: group.qualityLabel
        case .site: group.siteLabel
        case .destination: group.destinationLabel
        case .clientUsed: group.clientUsedLabel
        default: nil
        }
    }

    private func groupBlockAddedAt(_ block: GroupBlock) -> Double {
        block.allChildren.map(\.snapshot.addedAt).max()?.timeIntervalSince1970 ?? 0
    }

    private func originalIndex(_ block: VisibleBlock) -> Int {
        switch block {
        case let .single(_, index): index
        case let .group(block): block.originalIndex
        }
    }

    private func playlistIndexSort(_ lhs: RowModel, _ rhs: RowModel) -> Bool {
        let left = lhs.snapshot.playlistIndex ?? Int.max
        let right = rhs.snapshot.playlistIndex ?? Int.max
        if left == right {
            return lhs.snapshot.addedAt < rhs.snapshot.addedAt
        }
        return left < right
    }

    private func groupTitle(
        registry: PersistedPlaylistGroup?,
        children: [JobSnapshot]
    ) -> String {
        if let title = trimmedRegistryTitle(registry) {
            return title
        }
        return children.compactMap(\.title).first { !$0.isEmpty } ?? "Playlist"
    }

    private func trimmedRegistryTitle(_ registry: PersistedPlaylistGroup?) -> String? {
        let title = registry?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? nil : title
    }

    private func rollupFraction(_ snapshots: [JobSnapshot]) -> Double {
        guard !snapshots.isEmpty else { return 0 }
        let total = snapshots.reduce(0) { sum, snapshot in
            sum + progressContribution(snapshot)
        }
        return total / Double(snapshots.count)
    }

    private func progressContribution(_ snapshot: JobSnapshot) -> Double {
        Double(Self.progressBucket(for: snapshot)) / 10
    }

    private func activeSpeed(_ snapshots: [JobSnapshot]) -> Double {
        snapshots.reduce(0) { total, snapshot in
            guard snapshot.state == .running else { return total }
            return total + (snapshot.progress?.speedBytesPerSec ?? 0)
        }
    }

    private func activeEta(_ snapshots: [JobSnapshot]) -> Int? {
        let values = snapshots.compactMap { snapshot -> Int? in
            guard snapshot.state == .running else { return nil }
            return snapshot.progress?.etaSeconds
        }
        return values.max()
    }

    private func sumKnown<T: AdditiveArithmetic>(_ values: [T]) -> T? {
        guard !values.isEmpty else { return nil }
        return values.reduce(.zero) { $0 + $1 }
    }

    private func groupFinishedAt(_ snapshots: [JobSnapshot]) -> Date? {
        guard !snapshots.isEmpty, snapshots.allSatisfy({ $0.state == .completed }) else {
            return nil
        }
        return snapshots.compactMap(\.finishedAt).max()
    }

    private func common(_ values: [String]) -> String {
        guard let first = values.first else { return "—" }
        return values.allSatisfy { $0 == first } ? first : "mixed"
    }

    private func statusText(total: Int, completed: Int, failed: Int) -> String {
        "\(completed) done · \(failed) failed · \(total - completed - failed) queued"
    }

    private func isFailed(_ state: JobState) -> Bool {
        if case .failed = state {
            return true
        }
        return false
    }

    private func isCancellable(_ state: JobState) -> Bool {
        switch state {
        case .queued, .paused, .probing, .running:
            true
        default:
            false
        }
    }
}
