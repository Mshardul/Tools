import Foundation
import GrabberKit

public final class EventCollector: @unchecked Sendable {
    private struct State {
        var events: [QueueEvent] = []
        var lastSnapshot: QueueSnapshot?
    }

    private let box = LockedBox(State())
    private var task: Task<Void, Never>?

    public init(_ stream: AsyncStream<QueueEvent>) {
        task = Task { [box] in
            for await event in stream {
                box.mutate { state in
                    state.events.append(event)
                    if case let .snapshot(snap) = event {
                        state.lastSnapshot = snap
                    }
                }
            }
        }
    }

    public var all: [QueueEvent] {
        box.read { $0.events }
    }

    public var snapshots: [QueueSnapshot] {
        box.read {
            $0.events.compactMap { event in
                if case let .snapshot(snap) = event {
                    snap
                } else {
                    nil
                }
            }
        }
    }

    public func latestSnapshot() -> QueueSnapshot? {
        box.read { $0.lastSnapshot }
    }

    public func revisions() -> [UInt64] {
        box.read {
            $0.events.map { event in
                switch event {
                case let .snapshot(snap): snap.revision
                case let .progress(_, revision): revision
                }
            }
        }
    }

    public func waitForState(
        _ id: UUID,
        _ predicate: @escaping (JobState) -> Bool,
        timeout: TimeInterval = 5
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if matches(id, predicate) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func matches(_ id: UUID, _ predicate: (JobState) -> Bool) -> Bool {
        guard let job = latestSnapshot()?.jobs.first(where: { $0.id == id }) else { return false }
        return predicate(job.state)
    }

    deinit { task?.cancel() }
}
