@testable import GrabberKit
import XCTest

final class SchedulerTests: XCTestCase {
    private func job(_ index: Int, state: JobState = .queued, probed: Bool = true) -> JobSnapshot {
        JobSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")!,
            url: "u\(index)", title: probed ? "t" : nil, state: state, progress: nil,
            kind: .video(maxHeight: 1080),
            durationSeconds: probed ? 10 : nil, extractor: probed ? "youtube" : nil,
            addedAt: Date(timeIntervalSince1970: TimeInterval(index)), finishedAt: nil,
            destFolder: URL(fileURLWithPath: "/tmp"), outputFiles: [], sizeBytes: nil,
            actualQuality: nil, attempt: 0, cooldownUntil: nil, playerClientUsed: nil,
            playlistGroupID: nil, integrityVerdict: nil, availableActions: []
        )
    }

    private func input(
        queued: [JobSnapshot] = [], running: [JobSnapshot] = [],
        cap: Int = 2, deferred: Set<UUID> = [], probeIdle: Bool = true
    ) -> SchedulerInput {
        SchedulerInput(
            queued: queued, running: running, cap: cap,
            deferredIDs: deferred, probeIdle: probeIdle
        )
    }

    func test_empty() {
        XCTAssertEqual(Scheduler.nextDownloads(input()), [])
        XCTAssertNil(Scheduler.nextProbe(input()))
    }

    func test_runningBelowCap_fillsInQueueOrder() {
        let queue = [job(1), job(2), job(3)]
        XCTAssertEqual(
            Scheduler.nextDownloads(input(queued: queue, cap: 2)),
            [queue[0].id, queue[1].id]
        )
    }

    func test_runningAtCap_downloadsEmpty_butProbeStillRuns() {
        let queue = [job(1, probed: false)]
        let running = [job(4, state: .running), job(5, state: .running)]
        XCTAssertEqual(
            Scheduler.nextDownloads(input(queued: queue, running: running, cap: 2)),
            []
        )
        XCTAssertEqual(
            Scheduler.nextProbe(input(queued: queue, running: running, cap: 2)),
            queue[0].id
        )
    }

    func test_deferredIdSkipped() {
        let queue = [job(1), job(2)]
        XCTAssertEqual(
            Scheduler.nextDownloads(input(queued: queue, cap: 2, deferred: [queue[0].id])),
            [queue[1].id]
        )
    }

    func test_unprobedJobNotInDownloads() {
        let queue = [job(1, probed: false), job(2)]
        XCTAssertEqual(Scheduler.nextDownloads(input(queued: queue, cap: 2)), [queue[1].id])
    }

    func test_probeNotIdle_noProbe() {
        let queue = [job(1, probed: false)]
        XCTAssertNil(Scheduler.nextProbe(input(queued: queue, probeIdle: false)))
    }

    func test_probeReturnsHeadNeedingMetadata() {
        let queue = [job(1), job(2, probed: false), job(3, probed: false)]
        XCTAssertEqual(Scheduler.nextProbe(input(queued: queue)), queue[1].id)
    }
}
