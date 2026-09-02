import Foundation

// Engine-internal mutable model, isolated to DownloadEngine's actor; the UI binds to JobSnapshot.
final class DownloadJob {
    let id: UUID
    var request: DownloadRequest
    var title: String?
    var extractor: String?
    var durationSeconds: Int?
    var state: JobState
    var progress: Progress?
    var sizeBytes: Int64?
    var attempt: Int
    var forceCookies: Bool
    var outputFiles: [URL]
    // Runtime-only (not persisted) — set on completion / a failed integrity check.
    var integrityVerdict: IntegrityVerdict?
    var actualQuality: String?
    var capturedOutputPaths: [URL] = []
    let addedAt: Date
    var finishedAt: Date?
    // Force-start evicts the oldest-startedAt running job.
    var startedAt: Date?

    init(request: DownloadRequest, id: UUID = UUID(), addedAt: Date = .now) {
        self.id = id
        self.request = request
        self.addedAt = addedAt
        title = nil
        extractor = nil
        durationSeconds = nil
        state = .queued
        progress = nil
        sizeBytes = nil
        attempt = 0
        forceCookies = false
        outputFiles = []
        integrityVerdict = nil
        actualQuality = nil
        finishedAt = nil
        startedAt = nil
    }

    func snapshot(availableActions: Set<RowAction>) -> JobSnapshot {
        JobSnapshot(
            id: id,
            url: request.url,
            title: title,
            state: state,
            progress: progress,
            kind: request.kind,
            durationSeconds: durationSeconds,
            extractor: extractor,
            addedAt: addedAt,
            finishedAt: finishedAt,
            destFolder: request.destFolder,
            outputFiles: outputFiles,
            sizeBytes: sizeBytes,
            actualQuality: actualQuality,
            attempt: attempt,
            cooldownUntil: nil,
            playerClientUsed: nil,
            playlistGroupID: nil,
            integrityVerdict: integrityVerdict,
            availableActions: availableActions
        )
    }
}
