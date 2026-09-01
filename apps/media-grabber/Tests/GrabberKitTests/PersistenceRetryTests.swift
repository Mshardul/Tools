@testable import GrabberKit
import XCTest

// Phase 4 persistence guard-rails: attempt round-trips, a restored failure offers Retry.
final class PersistenceRetryTests: XCTestCase {
    private func request() -> DownloadRequest {
        DownloadRequest(
            url: "https://archive.org/x",
            destFolder: URL(fileURLWithPath: "/tmp/out"),
            kind: .video(maxHeight: 1080),
            container: "mp4",
            filenameTemplate: "%(title)s.%(ext)s"
        )
    }

    func test_queuedJobWithAttemptRoundTrips() throws {
        let persisted = PersistedJob(
            id: UUID(),
            request: request(),
            title: "t",
            extractor: "youtube",
            durationSeconds: 10,
            state: .queued,
            attempt: 3,
            playlistGroupID: nil,
            addedAt: .init(),
            finishedAt: nil
        )
        let file = QueueFile(schemaVersion: 1, jobs: [persisted])
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(QueueFile.self, from: data)
        XCTAssertEqual(decoded.jobs.first?.attempt, 3)
        XCTAssertEqual(decoded.jobs.first?.state, .queued)

        let restored = try DownloadEngine.downloadJob(from: XCTUnwrap(decoded.jobs.first))
        XCTAssertEqual(restored.attempt, 3)
        XCTAssertEqual(restored.state, .queued)
    }

    func test_restoredFailedJobIsUnknownRawAndOffersRetry() {
        let persisted = PersistedJob(
            id: UUID(),
            request: request(),
            title: "t",
            extractor: "youtube",
            durationSeconds: 10,
            state: .failed(reason: "rate_limited"),
            attempt: 2,
            playlistGroupID: nil,
            addedAt: .init(),
            finishedAt: .init()
        )
        let restored = DownloadEngine.downloadJob(from: persisted)
        guard case let .failed(errorClass) = restored.state else {
            return XCTFail("expected .failed")
        }
        XCTAssertEqual(errorClass, .unknown(raw: "rate_limited"))
        XCTAssertTrue(errorClass.presentation.offeredActions.contains(.retry))
    }
}
