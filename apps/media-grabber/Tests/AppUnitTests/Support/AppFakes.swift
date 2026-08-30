import Foundation
@testable import GrabberKit
@testable import MediaGrabber
import TestSupport

final class FakeEngine: DownloadEngineProtocol, @unchecked Sendable {
    private let box = LockedBox(State())
    private let continuation: AsyncStream<QueueEvent>.Continuation

    let events: AsyncStream<QueueEvent>

    private struct State {
        var submitted: [DownloadRequest] = []
        var cancelled: [UUID] = []
        var nextResult: SubmitResult?
    }

    init() {
        let (stream, continuation) = AsyncStream<QueueEvent>.makeStream()
        events = stream
        self.continuation = continuation
    }

    var submittedRequests: [DownloadRequest] {
        box.read { $0.submitted }
    }

    var cancelledIDs: [UUID] {
        box.read { $0.cancelled }
    }

    func stubNextResult(_ result: SubmitResult) {
        box.mutate { $0.nextResult = result }
    }

    func emit(_ event: QueueEvent) {
        continuation.yield(event)
    }

    func currentSnapshot() async -> QueueSnapshot {
        QueueSnapshot(jobs: [], revision: 0, queueHalt: nil, generatedAt: .init())
    }

    func hasActiveJobs() async -> Bool {
        false
    }

    func submit(
        _ request: DownloadRequest,
        force _: Bool,
        prefetchedMetadata _: MediaMetadata?
    ) async -> SubmitResult {
        box.mutate { $0.submitted.append(request) }
        return box.read { $0.nextResult } ?? .queued(UUID())
    }

    func restore(active _: [PersistedJob], history _: [PersistedJob]) async {}
    func revalidate() async {}
    func pause(_: UUID) async {}
    func resume(_: UUID) async {}

    func cancel(_ jobID: UUID) async {
        box.mutate { $0.cancelled.append(jobID) }
    }

    func remove(_: UUID) async {}
    func forceStart(_: UUID) async {}
    func shutdown() async {}
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
