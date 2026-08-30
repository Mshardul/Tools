import Foundation
import GrabberKit

public final class FakeQueuePersisting: QueuePersisting, @unchecked Sendable {
    private struct State {
        var queueSaves: [[PersistedJob]] = []
        var historySaves: [[PersistedJob]] = []
        var columnSaves: [ColumnConfig] = []
        var flushes = 0
        var cannedQueue: [PersistedJob] = []
        var cannedHistory: [PersistedJob] = []
        var cannedColumns: ColumnConfig?
    }

    private let box = LockedBox(State())

    public init() {}

    public var queueSaves: [[PersistedJob]] {
        box.read { $0.queueSaves }
    }

    public var historySaves: [[PersistedJob]] {
        box.read { $0.historySaves }
    }

    public var columnSaves: [ColumnConfig] {
        box.read { $0.columnSaves }
    }

    public var flushCount: Int {
        box.read { $0.flushes }
    }

    public var lastQueueSave: [PersistedJob]? {
        box.read { $0.queueSaves.last }
    }

    public var lastHistorySave: [PersistedJob]? {
        box.read { $0.historySaves.last }
    }

    public func stubQueue(_ jobs: [PersistedJob]) {
        box.mutate { $0.cannedQueue = jobs }
    }

    public func stubHistory(_ jobs: [PersistedJob]) {
        box.mutate { $0.cannedHistory = jobs }
    }

    public func stubColumns(_ config: ColumnConfig?) {
        box.mutate { $0.cannedColumns = config }
    }

    public func saveQueue(_ jobs: [PersistedJob]) {
        box.mutate { $0.queueSaves.append(jobs) }
    }

    public func saveHistory(_ jobs: [PersistedJob]) {
        box.mutate { $0.historySaves.append(jobs) }
    }

    public func saveColumns(_ config: ColumnConfig) {
        box.mutate { $0.columnSaves.append(config) }
    }

    public func flushNow() async {
        box.mutate { $0.flushes += 1 }
    }

    public func loadQueue() -> [PersistedJob] {
        box.read { $0.cannedQueue }
    }

    public func loadHistory() -> [PersistedJob] {
        box.read { $0.cannedHistory }
    }

    public func loadColumns() -> ColumnConfig? {
        box.read { $0.cannedColumns }
    }
}
