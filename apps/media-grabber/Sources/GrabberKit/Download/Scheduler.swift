import Foundation

// A struct so scheduling inputs can grow without touching either function signature.
public struct SchedulerInput: Sendable {
    public var queued: [JobSnapshot]
    public var running: [JobSnapshot]
    public var cap: Int
    public var deferredIDs: Set<UUID>
    public var probeIdle: Bool

    public init(
        queued: [JobSnapshot],
        running: [JobSnapshot],
        cap: Int,
        deferredIDs: Set<UUID>,
        probeIdle: Bool
    ) {
        self.queued = queued
        self.running = running
        self.cap = cap
        self.deferredIDs = deferredIDs
        self.probeIdle = probeIdle
    }
}

public enum Scheduler {
    public static func nextDownloads(_ input: SchedulerInput) -> [UUID] {
        let slots = max(0, input.cap - input.running.count)
        guard slots > 0 else { return [] }
        return input.queued
            .filter { isDownloadReady($0, deferredIDs: input.deferredIDs) }
            .prefix(slots)
            .map(\.id)
    }

    public static func nextProbe(_ input: SchedulerInput) -> UUID? {
        guard input.probeIdle else { return nil }
        return input.queued.first(where: needsMetadata)?.id
    }

    private static func isDownloadReady(_ job: JobSnapshot, deferredIDs: Set<UUID>) -> Bool {
        !needsMetadata(job) && !deferredIDs.contains(job.id)
    }

    private static func needsMetadata(_ job: JobSnapshot) -> Bool {
        job.title == nil || job.extractor == nil || job.durationSeconds == nil
    }
}
