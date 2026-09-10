import Foundation
import GrabberKit
import Observation

enum FilterChip: String, CaseIterable {
    case all, downloading, done, needsAttention
}

struct ChipCounts: Equatable {
    var all = 0
    var downloading = 0
    var done = 0
    var needsAttention = 0
}

enum VisibleItem: Equatable, Identifiable {
    case header(PlaylistGroup)
    case child(RowModel)

    var id: String {
        switch self {
        case let .header(group): "g-\(group.id)"
        case let .child(row): "j-\(row.id)"
        }
    }

    static func == (lhs: VisibleItem, rhs: VisibleItem) -> Bool {
        switch (lhs, rhs) {
        case let (.header(left), .header(right)):
            left == right
        case let (.child(left), .child(right)):
            left.id == right.id
        default:
            false
        }
    }
}

struct PlaylistGroup: Identifiable, Equatable {
    let id: UUID
    let title: String
    let totalCount: Int
    let completedCount: Int
    let failedCount: Int
    let runningCount: Int
    let cancellableCount: Int
    let rollupFraction: Double
    let speedBytesPerSec: Double
    let etaSeconds: Int?
    let sizeBytes: Int64?
    let durationSeconds: Int?
    let addedAt: Date
    let finishedAt: Date?
    let siteLabel: String
    let typeLabel: String
    let qualityLabel: String
    let destinationLabel: String
    let clientUsedLabel: String
    let attempt: Int
    let statusText: String
    var isCollapsed: Bool
}

@MainActor
@Observable
final class RowStore {
    private(set) var rows: [RowModel] = []
    private(set) var visibleRows: [RowModel] = []
    var visibleItems: [VisibleItem] = []
    var groups: [PlaylistGroup] = []
    private(set) var chipCounts = ChipCounts()

    var activeChip: FilterChip = .all {
        didSet { recomputeVisible() }
    }

    var columnConfig: ColumnConfig
    private var modelsByID: [UUID: RowModel] = [:]
    var groupRegistry: [UUID: PersistedPlaylistGroup] = [:]
    var localCollapsed: [UUID: Bool] = [:]
    private var progressBuckets: [UUID: Int] = [:]
    private(set) var lastRevision: UInt64 = 0

    init(columnConfig: ColumnConfig = .default) {
        self.columnConfig = columnConfig
    }

    func setColumnConfig(_ config: ColumnConfig) {
        columnConfig = config
        recomputeVisible()
    }

    // Live Preferences.maxAutoRetries forwarded to RowModel; defaulted so RowStore stays Preferences-free.
    private var maxAutoRetries = 5
    private var vpnActive = false

    // MARK: - Event ingestion

    func apply(_ event: QueueEvent, maxAutoRetries: Int = 5, vpnActive: Bool = false) {
        self.maxAutoRetries = maxAutoRetries
        self.vpnActive = vpnActive
        switch event {
        case let .snapshot(snapshot):
            applySnapshot(snapshot)
        case let .progress(delta, revision):
            guard revision >= lastRevision else { return }
            lastRevision = revision
            for (id, progress) in delta {
                modelsByID[id]?.patchProgress(fraction: progress)
            }
            if sortIsProgressLike || delta.keys.contains(where: progressBucketChanged) {
                recomputeVisible()
            }
        }
    }

    func resync(_ snapshot: QueueSnapshot, maxAutoRetries: Int = 5, vpnActive: Bool = false) {
        self.maxAutoRetries = maxAutoRetries
        self.vpnActive = vpnActive
        modelsByID.removeAll()
        rows = []
        applySnapshot(snapshot)
    }

    private func applySnapshot(_ snapshot: QueueSnapshot) {
        guard snapshot.revision >= lastRevision else { return }
        lastRevision = snapshot.revision

        let incomingIDs = Set(snapshot.jobs.map(\.id))
        modelsByID = modelsByID.filter { incomingIDs.contains($0.key) }

        var structuralChange = rows.count != snapshot.jobs.count
        var groupBucketChange = false
        var newRows: [RowModel] = []
        newRows.reserveCapacity(snapshot.jobs.count)

        let summary = snapshot.hostRateSummary
        var queuePosition = 0
        for job in snapshot.jobs {
            groupBucketChange = groupBucketChange || progressBuckets[job.id] != Self.progressBucket(for: job)
            appendRow(
                for: job,
                summary: summary,
                queuePosition: &queuePosition,
                structuralChange: &structuralChange,
                rows: &newRows
            )
        }

        if newRows.map(\.id) != rows.map(\.id) {
            structuralChange = true
        }
        rows = newRows
        pruneProgressBuckets(keeping: incomingIDs)
        for job in snapshot.jobs {
            progressBuckets[job.id] = Self.progressBucket(for: job)
        }
        recomputeChipCounts()

        if structuralChange || sortIsProgressLike || groupBucketChange {
            recomputeVisible()
        }
    }

    private func appendRow(
        for job: JobSnapshot,
        summary: [RateHost: HostRateDisplayState],
        queuePosition: inout Int,
        structuralChange: inout Bool,
        rows newRows: inout [RowModel]
    ) {
        let position = nextQueuePosition(for: job, queuePosition: &queuePosition)
        let rate = summary[job.rateHost]
        if let existing = modelsByID[job.id] {
            let changed = existing.patch(
                job,
                queuePosition: position,
                maxAutoRetries: maxAutoRetries,
                rate: rate,
                vpnActive: vpnActive
            )
            structuralChange = structuralChange || changed
            newRows.append(existing)
        } else {
            appendNewRow(job, position: position, rate: rate, rows: &newRows)
            structuralChange = true
        }
    }

    private func appendNewRow(
        _ job: JobSnapshot,
        position: Int?,
        rate: HostRateDisplayState?,
        rows newRows: inout [RowModel]
    ) {
        let model = RowModel(
            job,
            queuePosition: position,
            maxAutoRetries: maxAutoRetries,
            rate: rate,
            vpnActive: vpnActive
        )
        modelsByID[job.id] = model
        newRows.append(model)
    }

    private func nextQueuePosition(for job: JobSnapshot, queuePosition: inout Int) -> Int? {
        guard job.state == .queued else { return nil }
        queuePosition += 1
        return queuePosition
    }

    // MARK: - Derived state

    private var sortIsProgressLike: Bool {
        switch columnConfig.sortColumn {
        case .progress, .speed, .eta, .size: true
        default: false
        }
    }

    private func recomputeChipCounts() {
        var counts = ChipCounts()
        for row in rows {
            counts.all += 1
            switch row.snapshot.state {
            case .probing, .running, .queued, .paused:
                counts.downloading += 1
            case .completed:
                counts.done += 1
            case .cancelled:
                break
            case .failed, .cooldown:
                counts.needsAttention += 1
            case .waitingForNetwork:
                counts.downloading += 1
            }
        }
        chipCounts = counts
    }

    func recomputeVisible() {
        let filtered = rows.filter(passesChip).filter(passesColumnFilters)
        visibleRows = sorted(filtered)
        recomputeVisibleItems(filtered: filtered)
    }

    private func passesChip(_ row: RowModel) -> Bool {
        switch activeChip {
        case .all:
            true
        case .downloading:
            isDownloadingState(row.snapshot.state)
        case .done:
            row.snapshot.state == .completed
        case .needsAttention:
            isNeedsAttentionState(row.snapshot.state)
        }
    }

    private func isDownloadingState(_ state: JobState) -> Bool {
        switch state {
        case .queued, .probing, .running, .paused, .waitingForNetwork: true
        default: false
        }
    }

    private func isNeedsAttentionState(_ state: JobState) -> Bool {
        switch state {
        case .failed, .cooldown: true
        default: false
        }
    }

    private func passesColumnFilters(_ row: RowModel) -> Bool {
        for (column, allowed) in columnConfig.columnFilters where !allowed.isEmpty {
            let value = filterValue(row, column: column)
            if !allowed.contains(value) {
                return false
            }
        }
        return true
    }

    private func filterValue(_ row: RowModel, column: ColumnID) -> String {
        switch column {
        case .title: row.snapshot.title ?? "—"
        case .type: row.typeLabel
        case .quality: row.qualityLabel
        case .site: row.siteLabel
        case .status: row.statusText
        case .destination: row.snapshot.destFolder.path
        case .clientUsed: row.snapshot.playerClientUsed ?? "—"
        default: ""
        }
    }

    private func sorted(_ input: [RowModel]) -> [RowModel] {
        guard let column = columnConfig.sortColumn else { return input }
        let ascending = columnConfig.sortDirection != .descending
        return input.sorted { lhs, rhs in
            let left = sortKey(lhs, column: column)
            let right = sortKey(rhs, column: column)
            switch (left, right) {
            case let (leftValue?, rightValue?):
                return ascending ? leftValue < rightValue : leftValue > rightValue
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            case (nil, nil):
                return false
            }
        }
    }

    private func progressBucketChanged(id: UUID) -> Bool {
        guard let row = modelsByID[id] else { return false }
        let next = Self.progressBucket(for: row.snapshot)
        defer { progressBuckets[id] = next }
        return progressBuckets[id] != next
    }

    private func pruneProgressBuckets(keeping ids: Set<UUID>) {
        progressBuckets = progressBuckets.filter { ids.contains($0.key) }
    }
}
