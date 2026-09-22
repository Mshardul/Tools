@testable import GrabberKit
@testable import MediaGrabber
import XCTest

final class BatchEligibilityTests: XCTestCase {
    private func snap(
        _ index: Int,
        actions: Set<RowAction>,
        state: JobState = .queued
    ) -> JobSnapshot {
        JobSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")!,
            url: "https://example.com/\(index)",
            rateHost: RateHost(urlString: "https://example.com/\(index)"),
            title: "Clip \(index)",
            state: state,
            progress: nil,
            kind: .video(maxHeight: 1080),
            durationSeconds: nil,
            extractor: nil,
            addedAt: Date(timeIntervalSince1970: TimeInterval(index)),
            finishedAt: nil,
            destFolder: URL(fileURLWithPath: "/tmp"),
            outputFiles: [],
            sizeBytes: nil,
            actualQuality: nil,
            attempt: 0,
            cooldownUntil: nil,
            playerClientUsed: nil,
            playlistGroupID: nil,
            integrityVerdict: nil,
            availableActions: actions
        )
    }

    func test_offersPauseOnlyWhenSomeRunning() {
        let snaps = [
            snap(1, actions: [.pause, .cancel], state: .running),
            snap(2, actions: [.remove], state: .completed)
        ]
        let verbs = BatchEligibility.offeredVerbs(snapshots: snaps)
        XCTAssertTrue(verbs.contains(.pause))
        XCTAssertFalse(verbs.contains(.resume))
        XCTAssertEqual(
            BatchEligibility.applicableIDs(verb: .pause, snapshots: snaps).count,
            1
        )
    }

    func test_forceStartOnlyWhenExactlyOneEligible() {
        let one = [snap(1, actions: [.forceStart, .cancel])]
        XCTAssertTrue(BatchEligibility.offeredVerbs(snapshots: one).contains(.forceStart))

        let two = [
            snap(1, actions: [.forceStart]),
            snap(2, actions: [.forceStart])
        ]
        XCTAssertFalse(BatchEligibility.offeredVerbs(snapshots: two).contains(.forceStart))

        let none = [snap(1, actions: [.cancel])]
        XCTAssertFalse(BatchEligibility.offeredVerbs(snapshots: none).contains(.forceStart))
    }

    func test_restartMapsToRetry() {
        let snaps = [snap(1, actions: [.retry, .remove], state: .failed(.unknown(raw: "x")))]
        let verbs = BatchEligibility.offeredVerbs(snapshots: snaps)
        XCTAssertTrue(verbs.contains(.retry))
        XCTAssertFalse(verbs.contains(.reveal))
        XCTAssertFalse(verbs.contains(.openInBrowser))
        XCTAssertFalse(verbs.contains(.showLog))
        XCTAssertFalse(verbs.contains(.retryWithCookies))
    }
}
