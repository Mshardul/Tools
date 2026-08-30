import Foundation

public enum SubmitResult: Sendable, Equatable {
    case queued(UUID)
    case duplicateExists(existing: UUID, wasCompleted: Bool)
}

public enum PersistedState: Sendable, Equatable, Codable {
    case queued, paused, completed, cancelled
    case failed(reason: String)
}

// Deliberately caseless for now — the deferred-start seam has no caller yet.
public enum DeferReason: Sendable, Equatable {}
