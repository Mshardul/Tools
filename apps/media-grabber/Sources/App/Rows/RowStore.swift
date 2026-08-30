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

// Populated and rendered once playlists ship; carried through the store empty until then.
struct PlaylistGroup: Identifiable, Equatable {
    let id: UUID
    let title: String
    let totalCount: Int
    let completedCount: Int
    let failedCount: Int
    let rollupFraction: Double
    var isCollapsed: Bool
}

@MainActor
@Observable
final class RowStore {
    private(set) var rows: [RowModel] = []
    private(set) var visibleRows: [RowModel] = []
    private(set) var groups: [PlaylistGroup] = []
    private(set) var chipCounts = ChipCounts()

    var activeChip: FilterChip = .all {
        didSet { recomputeVisible() }
    }

    private var columnConfig: ColumnConfig
    private var modelsByID: [UUID: RowModel] = [:]
    private(set) var lastRevision: UInt64 = 0

    init(columnConfig: ColumnConfig = .default) {
        self.columnConfig = columnConfig
    }

    func setColumnConfig(_ config: ColumnConfig) {
        columnConfig = config
        recomputeVisible()
    }

    // MARK: - Event ingestion

    func apply(_ event: QueueEvent) {
        switch event {
        case let .snapshot(snapshot):
            applySnapshot(snapshot)
        case let .progress(delta, revision):
            guard revision >= lastRevision else { return }
            lastRevision = revision
            for (id, progress) in delta {
                modelsByID[id]?.patchProgress(fraction: progress)
            }
            if sortIsProgressLike {
                recomputeVisible()
            }
        }
    }

    func resync(_ snapshot: QueueSnapshot) {
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
        var newRows: [RowModel] = []
        newRows.reserveCapacity(snapshot.jobs.count)

        var queuePosition = 0
        for job in snapshot.jobs {
            let position: Int?
            if job.state == .queued {
                queuePosition += 1
                position = queuePosition
            } else {
                position = nil
            }
            if let existing = modelsByID[job.id] {
                let changed = existing.patch(job, queuePosition: position)
                structuralChange = structuralChange || changed
                newRows.append(existing)
            } else {
                let model = RowModel(job, queuePosition: position)
                modelsByID[job.id] = model
                newRows.append(model)
                structuralChange = true
            }
        }

        if newRows.map(\.id) != rows.map(\.id) {
            structuralChange = true
        }
        rows = newRows
        recomputeChipCounts()

        if structuralChange || sortIsProgressLike {
            recomputeVisible()
        }
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

    private func recomputeVisible() {
        let filtered = rows.filter(passesChip).filter(passesColumnFilters)
        visibleRows = sorted(filtered)
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

    private func sortKey(_ row: RowModel, column: ColumnID) -> Double? {
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
}
