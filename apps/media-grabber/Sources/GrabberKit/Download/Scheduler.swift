import Foundation

// A struct so scheduling inputs can grow without touching either function signature.
public struct SchedulerInput: Sendable {
    public var queued: [JobSnapshot]
    public var running: [JobSnapshot]
    public var cap: Int
    public var deferredIDs: Set<UUID>
    public var blockedHostIDs: Set<UUID>
    public var blockedProbeHostIDs: Set<UUID>
    public var probeIdle: Bool

    public init(
        queued: [JobSnapshot],
        running: [JobSnapshot],
        cap: Int,
        deferredIDs: Set<UUID>,
        blockedHostIDs: Set<UUID> = [],
        blockedProbeHostIDs: Set<UUID> = [],
        probeIdle: Bool
    ) {
        self.queued = queued
        self.running = running
        self.cap = cap
        self.deferredIDs = deferredIDs
        self.blockedHostIDs = blockedHostIDs
        self.blockedProbeHostIDs = blockedProbeHostIDs
        self.probeIdle = probeIdle
    }
}

public enum Scheduler {
    public static func nextDownloads(_ input: SchedulerInput) -> [UUID] {
        let slots = max(0, input.cap - input.running.count)
        guard slots > 0 else { return [] }
        return input.queued
            .filter { isDownloadReady($0, deferredIDs: input.deferredIDs, blockedHostIDs: input.blockedHostIDs) }
            .prefix(slots)
            .map(\.id)
    }

    public static func nextProbe(_ input: SchedulerInput) -> UUID? {
        guard input.probeIdle else { return nil }
        return input.queued.first { needsMetadata($0) && !input.blockedProbeHostIDs.contains($0.id) }?.id
    }

    private static func isDownloadReady(
        _ job: JobSnapshot,
        deferredIDs: Set<UUID>,
        blockedHostIDs: Set<UUID>
    ) -> Bool {
        !needsMetadata(job) && !deferredIDs.contains(job.id) && !blockedHostIDs.contains(job.id)
    }

    private static func needsMetadata(_ job: JobSnapshot) -> Bool {
        job.title == nil || job.extractor == nil || job.durationSeconds == nil
    }
}
