@testable import GrabberKit
@testable import MediaGrabber
import XCTest

@MainActor
final class RowStoreSelectionTests: XCTestCase {
    private func snap(_ index: Int, state: JobState) -> JobSnapshot {
        JobSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")!,
            url: "https://archive.org/details/\(index)",
            rateHost: RateHost(urlString: "https://archive.org/details/\(index)"),
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
            availableActions: []
        )
    }

    private func queueSnapshot(_ jobs: [JobSnapshot]) -> QueueSnapshot {
        QueueSnapshot(
            jobs: jobs,
            revision: 1,
            queueHalt: nil,
            generatedAt: .init(),
            hostRateSummary: [:],
            isOnline: true
        )
    }

    func test_chipChangePrunesSelection() {
        let store = RowStore()
        let running = snap(1, state: .running)
        let done = snap(2, state: .completed)
        store.apply(.snapshot(queueSnapshot([running, done])))
        store.setSelectedJobIDs([running.id, done.id], anchor: running.id)
        XCTAssertEqual(store.selectedJobIDs.count, 2)

        store.activeChip = .downloading
        XCTAssertEqual(store.selectedJobIDs, [running.id])
        XCTAssertEqual(store.selectionAnchorID, running.id)
    }

    func test_selectAllVisibleIgnoresHeaders() {
        let store = RowStore()
        let first = snap(1, state: .queued)
        let second = snap(2, state: .queued)
        store.apply(.snapshot(queueSnapshot([first, second])))
        store.selectAllVisibleChildren()
        XCTAssertEqual(store.selectedJobIDs, [first.id, second.id])
        XCTAssertEqual(store.visibleChildOrder().count, 2)
    }

    func test_clearSelection() {
        let store = RowStore()
        let first = snap(1, state: .queued)
        store.apply(.snapshot(queueSnapshot([first])))
        store.setSelectedJobIDs([first.id], anchor: first.id)
        store.clearSelection()
        XCTAssertTrue(store.selectedJobIDs.isEmpty)
        XCTAssertNil(store.selectionAnchorID)
    }
}
