import Foundation

public enum SubmitResult: Sendable, Equatable {
    case queued(UUID)
    case duplicateExists(existing: UUID, wasCompleted: Bool)
}

public enum PersistedState: Sendable, Equatable, Codable {
    case queued, paused, completed, cancelled
    case failed(reason: String)
}

// The log discriminator for a deferred start. A per-host cooldown case joins this
// enum when that deferral source is built; the jobDeferred event already carries it.
public enum DeferReason: Sendable, Equatable {
    case backoff(attempt: Int)
}
