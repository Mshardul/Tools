@testable import GrabberKit
@testable import MediaGrabber
import XCTest

@MainActor
final class RowModelStatusTests: XCTestCase {
    private func snapshot(
        state: JobState = .queued,
        attempt: Int = 0,
        kind: DownloadKind = .video(maxHeight: 1080),
        actualQuality: String? = nil
    ) -> JobSnapshot {
        JobSnapshot(
            id: UUID(),
            url: "https://archive.org/details/x",
            title: "Clip",
            state: state,
            progress: nil,
            kind: kind,
            durationSeconds: nil,
            extractor: nil,
            addedAt: .init(),
            finishedAt: nil,
            destFolder: URL(fileURLWithPath: "/tmp"),
            outputFiles: [],
            sizeBytes: nil,
            actualQuality: actualQuality,
            attempt: attempt,
            cooldownUntil: nil,
            playerClientUsed: nil,
            playlistGroupID: nil,
            integrityVerdict: nil,
            availableActions: []
        )
    }

    func test_status_queuedWithAttemptShowsRetrying() {
        let snap = snapshot(state: .queued, attempt: 2)
        XCTAssertEqual(RowModel.status(for: snap, maxAutoRetries: 5), "Retrying — attempt 3 of 5")
    }

    func test_status_queuedAttemptZeroIsPlainQueued() {
        XCTAssertEqual(
            RowModel.status(for: snapshot(state: .queued, attempt: 0), maxAutoRetries: 5),
            "Queued"
        )
    }

    func test_status_failedUsesPresentationSentence() {
        let snap = snapshot(state: .failed(.rateLimited()), attempt: 5)
        XCTAssertEqual(
            RowModel.status(for: snap, maxAutoRetries: 5),
            "Failed — The site is limiting how fast we can download right now."
        )
    }

    func test_quality_actualDiffersShowsArrow() {
        let snap = snapshot(kind: .video(maxHeight: 1080), actualQuality: "720p")
        XCTAssertEqual(RowModel.quality(for: snap), "1080p → 720p")
    }

    func test_quality_actualMatchesShowsRequest() {
        let snap = snapshot(kind: .video(maxHeight: 1080), actualQuality: "1080p")
        XCTAssertEqual(RowModel.quality(for: snap), "1080p")
    }

    func test_quality_actualNilShowsRequest() {
        let snap = snapshot(kind: .video(maxHeight: 1080), actualQuality: nil)
        XCTAssertEqual(RowModel.quality(for: snap), "1080p")
    }

    func test_badge_hiddenWhileRetrying() {
        let retrying = RowModel(snapshot(state: .queued, attempt: 1), queuePosition: 3)
        XCTAssertNil(retrying.queueBadge)
        let fresh = RowModel(snapshot(state: .queued, attempt: 0), queuePosition: 3)
        XCTAssertEqual(fresh.queueBadge, "#3")
    }

    func test_patch_livePrefChangeUpdatesStatus() {
        let model = RowModel(
            snapshot(state: .queued, attempt: 2),
            queuePosition: nil,
            maxAutoRetries: 5
        )
        XCTAssertEqual(model.statusText, "Retrying — attempt 3 of 5")
        model.patch(snapshot(state: .queued, attempt: 2), queuePosition: nil, maxAutoRetries: 3)
        XCTAssertEqual(model.statusText, "Retrying — attempt 3 of 3")
    }
}
