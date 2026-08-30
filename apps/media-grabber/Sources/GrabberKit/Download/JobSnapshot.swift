import Foundation

public enum JobState: Sendable, Equatable {
    case queued
    case probing
    case running
    case paused
    case waitingForNetwork
    case cooldown(until: Date)
    case completed
    case cancelled
    case failed(ErrorClass)
}

public enum IntegrityVerdict: Sendable, Equatable {
    case passed
    case failed(reason: String)
    case skipped(reason: String)
}

public enum QueueHaltReason: Sendable, Equatable {
    case depMissing
}

public enum RowAction: Sendable, Hashable {
    case pause, resume, cancel, remove, forceStart, reveal, openInBrowser
    // Gated: the engine never puts these in a job's action set yet.
    case retry, retryWithCookies, showLog
}

public struct JobSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let url: String
    public let title: String?
    public let state: JobState
    public let progress: Progress?
    // RowStore derives type / quality from this; not otherwise stored.
    public let kind: DownloadKind
    public let durationSeconds: Int?
    public let extractor: String?
    public let addedAt: Date
    public let finishedAt: Date?
    public let destFolder: URL
    public let outputFiles: [URL]
    public let sizeBytes: Int64?
    public let actualQuality: String?
    public let attempt: Int
    public let cooldownUntil: Date?
    public let playerClientUsed: String?
    public let playlistGroupID: UUID?
    public let integrityVerdict: IntegrityVerdict?
    public let availableActions: Set<RowAction>

    public init(
        id: UUID,
        url: String,
        title: String?,
        state: JobState,
        progress: Progress?,
        kind: DownloadKind,
        durationSeconds: Int?,
        extractor: String?,
        addedAt: Date,
        finishedAt: Date?,
        destFolder: URL,
        outputFiles: [URL],
        sizeBytes: Int64?,
        actualQuality: String?,
        attempt: Int,
        cooldownUntil: Date?,
        playerClientUsed: String?,
        playlistGroupID: UUID?,
        integrityVerdict: IntegrityVerdict?,
        availableActions: Set<RowAction>
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.state = state
        self.progress = progress
        self.kind = kind
        self.durationSeconds = durationSeconds
        self.extractor = extractor
        self.addedAt = addedAt
        self.finishedAt = finishedAt
        self.destFolder = destFolder
        self.outputFiles = outputFiles
        self.sizeBytes = sizeBytes
        self.actualQuality = actualQuality
        self.attempt = attempt
        self.cooldownUntil = cooldownUntil
        self.playerClientUsed = playerClientUsed
        self.playlistGroupID = playlistGroupID
        self.integrityVerdict = integrityVerdict
        self.availableActions = availableActions
    }
}
