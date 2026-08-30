import Foundation

// The Codable projection of one engine job, round-tripped through queue.json / history.json.
public struct PersistedJob: Codable, Sendable, Equatable {
    public var id: UUID
    public var request: DownloadRequest
    public var title: String?
    public var extractor: String?
    public var durationSeconds: Int?
    public var state: PersistedState
    public var attempt: Int
    public var playlistGroupID: UUID?
    public var addedAt: Date
    public var finishedAt: Date?

    public init(
        id: UUID,
        request: DownloadRequest,
        title: String? = nil,
        extractor: String? = nil,
        durationSeconds: Int? = nil,
        state: PersistedState,
        attempt: Int = 0,
        playlistGroupID: UUID? = nil,
        addedAt: Date,
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.request = request
        self.title = title
        self.extractor = extractor
        self.durationSeconds = durationSeconds
        self.state = state
        self.attempt = attempt
        self.playlistGroupID = playlistGroupID
        self.addedAt = addedAt
        self.finishedAt = finishedAt
    }
}

public extension PersistedState {
    // Live state clamps on write: running / probing / cooldown / waitingForNetwork → queued.
    static func persisted(from state: JobState) -> PersistedState {
        switch state {
        case .queued, .probing, .running, .waitingForNetwork, .cooldown:
            .queued
        case .paused:
            .paused
        case .completed:
            .completed
        case .cancelled:
            .cancelled
        case let .failed(errorClass):
            .failed(reason: Self.reason(for: errorClass))
        }
    }

    // A restored failure keeps its text but loses its original ErrorClass case.
    var restoredJobState: JobState {
        switch self {
        case .queued: .queued
        case .paused: .paused
        case .completed: .completed
        case .cancelled: .cancelled
        case let .failed(reason): .failed(.unknown(raw: reason))
        }
    }

    private static func reason(for errorClass: ErrorClass) -> String {
        if case let .unknown(raw) = errorClass {
            return raw
        }
        return "\(errorClass)"
    }
}

public extension PersistedJob {
    // Probe-complete when title, extractor and durationSeconds are all present.
    var isProbeComplete: Bool {
        title != nil && extractor != nil && durationSeconds != nil
    }
}
