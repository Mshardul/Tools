import Foundation

public struct PlaylistGroupSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let sourceURL: String
    public let isCollapsed: Bool
    public let totalCount: Int
    public let completedCount: Int
    public let failedCount: Int
    public let runningCount: Int
    public let cancellableCount: Int
    public let rollupFraction: Double

    public init(
        id: UUID,
        title: String,
        sourceURL: String,
        isCollapsed: Bool,
        totalCount: Int,
        completedCount: Int,
        failedCount: Int,
        runningCount: Int,
        cancellableCount: Int,
        rollupFraction: Double
    ) {
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.isCollapsed = isCollapsed
        self.totalCount = totalCount
        self.completedCount = completedCount
        self.failedCount = failedCount
        self.runningCount = runningCount
        self.cancellableCount = cancellableCount
        self.rollupFraction = rollupFraction
    }

    public static func rollup(
        from jobs: [JobSnapshot],
        registry: PersistedPlaylistGroup
    ) -> PlaylistGroupSnapshot {
        let children = jobs.filter { $0.playlistGroupID == registry.id }
        let completed = children.filter { $0.state == .completed }.count
        let failed = children.filter { isFailed($0.state) }.count
        let running = children.filter { $0.state == .running }.count
        let cancellable = children.filter { isCancellable($0.state) }.count
        return PlaylistGroupSnapshot(
            id: registry.id,
            title: registry.title,
            sourceURL: registry.sourceURL,
            isCollapsed: registry.isCollapsed,
            totalCount: children.count,
            completedCount: completed,
            failedCount: failed,
            runningCount: running,
            cancellableCount: cancellable,
            rollupFraction: rollupFraction(children)
        )
    }

    public var asPersisted: PersistedPlaylistGroup {
        PersistedPlaylistGroup(
            id: id,
            title: title,
            sourceURL: sourceURL,
            isCollapsed: isCollapsed
        )
    }

    private static func isFailed(_ state: JobState) -> Bool {
        if case .failed = state {
            return true
        }
        return false
    }

    private static func isCancellable(_ state: JobState) -> Bool {
        switch state {
        case .queued, .paused, .probing, .running, .cooldown, .waitingForNetwork:
            true
        default:
            false
        }
    }

    private static func rollupFraction(_ snapshots: [JobSnapshot]) -> Double {
        guard !snapshots.isEmpty else { return 0 }
        let total = snapshots.reduce(0.0) { sum, snapshot in
            sum + progressContribution(snapshot)
        }
        return total / Double(snapshots.count)
    }

    private static func progressContribution(_ snapshot: JobSnapshot) -> Double {
        Double(progressBucket(for: snapshot)) / 10
    }

    private static func progressBucket(for snapshot: JobSnapshot) -> Int {
        guard snapshot.state != .completed, let fraction = snapshot.progress?.fraction else {
            return snapshot.state == .completed ? 10 : 0
        }
        return max(0, min(10, Int(fraction * 10)))
    }
}
