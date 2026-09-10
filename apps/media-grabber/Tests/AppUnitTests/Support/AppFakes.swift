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
        var paused: [UUID] = []
        var cancelled: [UUID] = []
        var removed: [UUID] = []
        var retried: [UUID] = []
        var retriedWithCookies: [UUID] = []
        var submitResults: [SubmitResult] = []
        var hasActive = false
        var snapshot = QueueSnapshot(
            jobs: [], revision: 0, queueHalt: nil, generatedAt: .init(),
            hostRateSummary: [:], isOnline: true
        )
        var restoreSnapshot: QueueSnapshot?
        var restoreCalled = false
        var revalidateCalled = false
        var shutdownCalled = false
        var previewResult: Result<MediaMetadata, MetadataError> = .failure(.malformedOutput)
        var previewPlaylistResult: Result<PlaylistDump, MetadataError> = .failure(.malformedOutput)
        var previewed: [String] = []
        var previewedPlaylists: [String] = []
        var submittedPlaylistItems: [PlaylistSubmitItem] = []
        var stubPlaylistSubmitIDs: [UUID]?
        var ensureCount = 0
        var restartCount = 0
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

    var pausedIDs: [UUID] {
        box.read { $0.paused }
    }

    var cancelledIDs: [UUID] {
        box.read { $0.cancelled }
    }

    var removedIDs: [UUID] {
        box.read { $0.removed }
    }

    var retriedIDs: [UUID] {
        box.read { $0.retried }
    }

    var retriedWithCookiesIDs: [UUID] {
        box.read { $0.retriedWithCookies }
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

    var previewedURLs: [String] {
        box.read { $0.previewed }
    }

    var previewPlaylistURLs: [String] {
        box.read { $0.previewedPlaylists }
    }

    var submittedPlaylistItems: [PlaylistSubmitItem] {
        box.read { $0.submittedPlaylistItems }
    }

    var ensureCount: Int {
        box.read { $0.ensureCount }
    }

    var restartCount: Int {
        box.read { $0.restartCount }
    }

    func stubPreview(_ result: Result<MediaMetadata, MetadataError>) {
        box.mutate { $0.previewResult = result }
    }

    func stubPreviewPlaylist(_ result: Result<PlaylistDump, MetadataError>) {
        box.mutate { $0.previewPlaylistResult = result }
    }

    func stubNextResult(_ result: SubmitResult) {
        box.mutate { $0.submitResults = [result] }
    }

    func stubSubmitResults(_ results: SubmitResult...) {
        box.mutate { $0.submitResults = results }
    }

    func stubPlaylistSubmitIDs(_ ids: [UUID]) {
        box.mutate { $0.stubPlaylistSubmitIDs = ids }
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

    func submitPlaylistItems(_ items: [PlaylistSubmitItem]) async -> [UUID] {
        box.mutate { state in
            state.submittedPlaylistItems.append(contentsOf: items)
        }
        if let stubbed = box.read { $0.stubPlaylistSubmitIDs } {
            return stubbed
        }
        return items.map { _ in UUID() }
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

    func pause(_ jobID: UUID) async {
        box.mutate { $0.paused.append(jobID) }
    }

    func resume(_: UUID) async {}

    func retry(_ jobID: UUID) async {
        box.mutate { $0.retried.append(jobID) }
    }

    func retryWithCookies(_ jobID: UUID) async {
        box.mutate { $0.retriedWithCookies.append(jobID) }
    }

    func cancel(_ jobID: UUID) async {
        box.mutate { $0.cancelled.append(jobID) }
    }

    func remove(_ jobID: UUID) async {
        box.mutate { $0.removed.append(jobID) }
    }

    func forceStart(_: UUID) async {}
    func resetCircuit(_: RateHost) async {}
    func resetAllCircuits() async {}

    func preview(_ url: String) async -> Result<MediaMetadata, MetadataError> {
        box.mutate { state in
            state.previewed.append(url)
            return state.previewResult
        }
    }

    func previewPlaylist(_ url: String) async -> Result<PlaylistDump, MetadataError> {
        box.mutate { state in
            state.previewedPlaylists.append(url)
            return state.previewPlaylistResult
        }
    }

    func ensureShield() async {
        box.mutate { $0.ensureCount += 1 }
    }

    func restartShield() async {
        box.mutate { $0.restartCount += 1 }
    }

    func shutdown() async {
        box.mutate { $0.shutdownCalled = true }
    }
}

final class FakeMetadataProbe: MetadataProbing, @unchecked Sendable {
    typealias Outcome = Result<MediaMetadata, MetadataError>
    typealias PlaylistOutcome = Result<PlaylistDump, MetadataError>
    private let box: LockedBox<Outcome>
    private let playlistBox: LockedBox<PlaylistOutcome>
    private let probed = LockedBox<[String]>([])
    private let playlistProbed = LockedBox<[String]>([])

    init(_ outcome: Outcome, playlistOutcome: PlaylistOutcome = .failure(.malformedOutput)) {
        box = LockedBox(outcome)
        playlistBox = LockedBox(playlistOutcome)
    }

    var probedURLs: [String] {
        probed.read { $0 }
    }

    var probedPlaylistURLs: [String] {
        playlistProbed.read { $0 }
    }

    func probe(_ url: String, context _: ExtractorContext) async -> Outcome {
        probed.mutate { $0.append(url) }
        return box.read { $0 }
    }

    func probePlaylist(_ url: String, context _: ExtractorContext) async -> PlaylistOutcome {
        playlistProbed.mutate { $0.append(url) }
        return playlistBox.read { $0 }
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
