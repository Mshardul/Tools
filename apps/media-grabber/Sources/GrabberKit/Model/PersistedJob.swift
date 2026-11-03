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
    public var playlistIndex: Int?
    public var addedAt: Date
    public var finishedAt: Date?
    public var sizeBytes: Int64?
    public var actualQuality: String?
    public var progressFraction: Double?
    public var downloadedBytes: Int64?
    public var totalBytes: Int64?
    public var outputFiles: [URL]
    public var playerClientUsed: String?

    public init(
        id: UUID,
        request: DownloadRequest,
        title: String? = nil,
        extractor: String? = nil,
        durationSeconds: Int? = nil,
        state: PersistedState,
        attempt: Int = 0,
        playlistGroupID: UUID? = nil,
        playlistIndex: Int? = nil,
        addedAt: Date,
        finishedAt: Date? = nil,
        sizeBytes: Int64? = nil,
        actualQuality: String? = nil,
        progressFraction: Double? = nil,
        downloadedBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        outputFiles: [URL] = [],
        playerClientUsed: String? = nil
    ) {
        self.id = id
        self.request = request
        self.title = title
        self.extractor = extractor
        self.durationSeconds = durationSeconds
        self.state = state
        self.attempt = attempt
        self.playlistGroupID = playlistGroupID
        self.playlistIndex = playlistIndex
        self.addedAt = addedAt
        self.finishedAt = finishedAt
        self.sizeBytes = sizeBytes
        self.actualQuality = actualQuality
        self.progressFraction = progressFraction
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.outputFiles = outputFiles
        self.playerClientUsed = playerClientUsed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        request = try container.decode(DownloadRequest.self, forKey: .request)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        extractor = try container.decodeIfPresent(String.self, forKey: .extractor)
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds)
        state = try container.decode(PersistedState.self, forKey: .state)
        attempt = try container.decodeIfPresent(Int.self, forKey: .attempt) ?? 0
        playlistGroupID = try container.decodeIfPresent(UUID.self, forKey: .playlistGroupID)
        playlistIndex = try container.decodeIfPresent(Int.self, forKey: .playlistIndex)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        sizeBytes = try container.decodeIfPresent(Int64.self, forKey: .sizeBytes)
        actualQuality = try container.decodeIfPresent(String.self, forKey: .actualQuality)
        progressFraction = try container.decodeIfPresent(Double.self, forKey: .progressFraction)
        downloadedBytes = try container.decodeIfPresent(Int64.self, forKey: .downloadedBytes)
        totalBytes = try container.decodeIfPresent(Int64.self, forKey: .totalBytes)
        outputFiles = try container.decodeIfPresent([URL].self, forKey: .outputFiles) ?? []
        playerClientUsed = try container.decodeIfPresent(String.self, forKey: .playerClientUsed)
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
