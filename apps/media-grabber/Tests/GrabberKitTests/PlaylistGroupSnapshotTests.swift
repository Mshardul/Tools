@testable import GrabberKit
import XCTest

final class PlaylistGroupSnapshotTests: XCTestCase {
    func testPlaylistGroupSnapshotRollupCountsChildren() {
        let id = UUID()
        let registry = PersistedPlaylistGroup(
            id: id, title: "PL", sourceURL: "https://x", isCollapsed: false
        )
        let dest = URL(fileURLWithPath: "/tmp")
        let jobs = [
            job(id: UUID(), group: id, state: .completed, dest: dest),
            job(id: UUID(), group: id, state: .failed(.unavailable), dest: dest),
            job(id: UUID(), group: id, state: .running, dest: dest),
            job(id: UUID(), group: id, state: .queued, dest: dest),
            job(id: UUID(), group: nil, state: .completed, dest: dest)
        ]
        let snap = PlaylistGroupSnapshot.rollup(from: jobs, registry: registry)
        XCTAssertEqual(snap.totalCount, 4)
        XCTAssertEqual(snap.completedCount, 1)
        XCTAssertEqual(snap.failedCount, 1)
        XCTAssertEqual(snap.runningCount, 1)
        XCTAssertEqual(snap.cancellableCount, 2)
        XCTAssertEqual(snap.isCollapsed, false)
        XCTAssertEqual(snap.title, "PL")
        XCTAssertEqual(snap.rollupFraction, 0.25, accuracy: 0.0001)
    }

    private func job(
        id: UUID,
        group: UUID?,
        state: JobState,
        dest: URL
    ) -> JobSnapshot {
        JobSnapshot(
            id: id,
            url: "https://example.com/\(id.uuidString)",
            rateHost: RateHost(urlString: "https://example.com"),
            title: "Clip",
            state: state,
            progress: nil,
            kind: .video(maxHeight: 1080),
            durationSeconds: 10,
            extractor: "youtube",
            addedAt: Date(timeIntervalSince1970: 1),
            finishedAt: nil,
            destFolder: dest,
            outputFiles: [],
            sizeBytes: nil,
            actualQuality: nil,
            attempt: 0,
            cooldownUntil: nil,
            playerClientUsed: nil,
            playlistGroupID: group,
            integrityVerdict: nil,
            availableActions: []
        )
    }
}
