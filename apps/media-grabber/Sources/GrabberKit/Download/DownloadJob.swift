import Foundation
import Observation

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

@MainActor
@Observable
public final class DownloadJob: Identifiable {
    public let id: UUID
    public let request: DownloadRequest
    public var title: String?
    public var state: JobState
    public var progress: Progress?
    public var attempt: Int
    public var playerClientUsed: String?
    public var outputFiles: [URL]
    public let addedAt: Date
    public var finishedAt: Date?

    public init(request: DownloadRequest, id: UUID = UUID(), addedAt: Date = .now) {
        self.id = id
        self.request = request
        self.addedAt = addedAt
        title = nil
        state = .queued
        progress = nil
        attempt = 0
        playerClientUsed = nil
        outputFiles = []
        finishedAt = nil
    }
}
