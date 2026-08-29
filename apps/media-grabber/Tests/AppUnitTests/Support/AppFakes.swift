import Foundation
@testable import GrabberKit
@testable import MediaGrabber

final class LockedBox<Value>: @unchecked Sendable {
    private var value: Value
    private let lock: os_unfair_lock_t

    init(_ value: Value) {
        self.value = value
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    func read<T>(_ body: (Value) -> T) -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return body(value)
    }

    @discardableResult
    func mutate<T>(_ body: (inout Value) -> T) -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return body(&value)
    }
}

final class FakeEngine: DownloadEngineProtocol, @unchecked Sendable {
    private let box = LockedBox(State())

    private struct State {
        var submitted: [DownloadRequest] = []
        var cancelled: [UUID] = []
    }

    var submittedRequests: [DownloadRequest] {
        box.read { $0.submitted }
    }

    var cancelledIDs: [UUID] {
        box.read { $0.cancelled }
    }

    @discardableResult
    func submit(_ request: DownloadRequest) async -> DownloadJob {
        box.mutate { $0.submitted.append(request) }
        return await MainActor.run { DownloadJob(request: request) }
    }

    func cancel(_ jobID: UUID) async {
        box.mutate { $0.cancelled.append(jobID) }
    }
}

final class FakeMetadataProbe: MetadataProbing, @unchecked Sendable {
    typealias Outcome = Result<MediaMetadata, MetadataError>
    private let box: LockedBox<Outcome>
    private let probed = LockedBox<[String]>([])

    init(_ outcome: Outcome) {
        box = LockedBox(outcome)
    }

    var probedURLs: [String] {
        probed.read { $0 }
    }

    func probe(_ url: String) async -> Outcome {
        probed.mutate { $0.append(url) }
        return box.read { $0 }
    }
}

final class FakeEnvironmentProbe: EnvironmentProbing, @unchecked Sendable {
    private let report: EnvironmentReport

    init(ready: Bool) {
        let tool = ToolInfo(path: URL(fileURLWithPath: "/opt/homebrew/bin/x"), version: "1")
        report = EnvironmentReport(
            brew: tool,
            ytDlp: ready ? tool : nil,
            ffmpeg: ready ? tool : nil
        )
    }

    func probe() async -> EnvironmentReport {
        report
    }
}

@MainActor
final class FakeRevealSink: RevealSink {
    private(set) var revealed: [URL] = []

    nonisolated init() {}

    func reveal(_ files: [URL]) {
        revealed = files
    }
}
