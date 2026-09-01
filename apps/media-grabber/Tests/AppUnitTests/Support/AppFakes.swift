import Foundation
@testable import GrabberKit
@testable import MediaGrabber
import TestSupport

final class FakeEngine: DownloadEngineProtocol, @unchecked Sendable {
    private let box = LockedBox(State())
    private let continuation: AsyncStream<QueueEvent>.Continuation

    let events: AsyncStream<QueueEvent>

    private struct State {
        var submitted: [(DownloadRequest, Bool)] = []
        var cancelled: [UUID] = []
        var retried: [UUID] = []
        var submitResults: [SubmitResult] = []
        var hasActive = false
        var snapshot = QueueSnapshot(jobs: [], revision: 0, queueHalt: nil, generatedAt: .init())
        var restoreSnapshot: QueueSnapshot?
        var restoreCalled = false
        var revalidateCalled = false
        var shutdownCalled = false
    }

    init() {
        let (stream, continuation) = AsyncStream<QueueEvent>.makeStream()
        events = stream
        self.continuation = continuation
    }

    var submittedRequests: [DownloadRequest] {
        box.read { $0.submitted.map(\.0) }
    }

    var submittedForces: [Bool] {
        box.read { $0.submitted.map(\.1) }
    }

    var cancelledIDs: [UUID] {
        box.read { $0.cancelled }
    }

    var retriedIDs: [UUID] {
        box.read { $0.retried }
    }

    var restoreCalled: Bool {
        box.read { $0.restoreCalled }
    }

    var revalidateCalled: Bool {
        box.read { $0.revalidateCalled }
    }

    var shutdownCalled: Bool {
        box.read { $0.shutdownCalled }
    }

    func stubNextResult(_ result: SubmitResult) {
        box.mutate { $0.submitResults = [result] }
    }

    func stubSubmitResults(_ results: SubmitResult...) {
        box.mutate { $0.submitResults = results }
    }

    func setHasActiveJobs(_ value: Bool) {
        box.mutate { $0.hasActive = value }
    }

    func setSnapshot(_ snapshot: QueueSnapshot) {
        box.mutate { $0.snapshot = snapshot }
    }

    func setRestoreSnapshot(_ snapshot: QueueSnapshot) {
        box.mutate { $0.restoreSnapshot = snapshot }
    }

    func emit(_ event: QueueEvent) {
        continuation.yield(event)
    }

    func currentSnapshot() async -> QueueSnapshot {
        box.read { $0.snapshot }
    }

    func hasActiveJobs() async -> Bool {
        box.read { $0.hasActive }
    }

    func submit(
        _ request: DownloadRequest,
        force: Bool,
        prefetchedMetadata _: MediaMetadata?
    ) async -> SubmitResult {
        let result: SubmitResult? = box.mutate { state in
            state.submitted.append((request, force))
            guard !state.submitResults.isEmpty else { return nil }
            return state.submitResults.removeFirst()
        }
        return result ?? .queued(UUID())
    }

    func restore(active _: [PersistedJob], history _: [PersistedJob]) async {
        let snapshot = box.mutate { state -> QueueSnapshot? in
            state.restoreCalled = true
            if let restoreSnapshot = state.restoreSnapshot {
                state.snapshot = restoreSnapshot
                return restoreSnapshot
            }
            return nil
        }
        if let snapshot {
            continuation.yield(.snapshot(snapshot))
        }
    }

    func revalidate() async {
        box.mutate { $0.revalidateCalled = true }
    }

    func pause(_: UUID) async {}
    func resume(_: UUID) async {}

    func retry(_ jobID: UUID) async {
        box.mutate { $0.retried.append(jobID) }
    }

    func cancel(_ jobID: UUID) async {
        box.mutate { $0.cancelled.append(jobID) }
    }

    func remove(_: UUID) async {}
    func forceStart(_: UUID) async {}

    func shutdown() async {
        box.mutate { $0.shutdownCalled = true }
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

@MainActor
final class FakeOpenURLSink: OpenURLSink {
    private(set) var opened: [URL] = []

    nonisolated init() {}

    func open(_ url: URL) {
        opened.append(url)
    }
}
