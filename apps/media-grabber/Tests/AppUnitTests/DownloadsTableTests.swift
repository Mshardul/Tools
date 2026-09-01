@testable import GrabberKit
@testable import MediaGrabber
import TestSupport
import XCTest

@MainActor
final class DownloadsTableTests: XCTestCase {
    private func snap(
        _ index: Int,
        state: JobState = .queued,
        sizeBytes: Int64? = nil,
        availableActions: Set<RowAction>? = nil
    ) -> JobSnapshot {
        JobSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")!,
            url: "https://archive.org/details/\(index)",
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
            sizeBytes: sizeBytes,
            actualQuality: nil,
            attempt: 0,
            cooldownUntil: nil,
            playerClientUsed: nil,
            playlistGroupID: nil,
            integrityVerdict: nil,
            availableActions: availableActions ?? DownloadEngine.availableActions(for: state)
        )
    }

    private func queueSnapshot(_ jobs: [JobSnapshot]) -> QueueSnapshot {
        QueueSnapshot(jobs: jobs, revision: 1, queueHalt: nil, generatedAt: .init())
    }

    func test_nilFieldRendersEmDash_columnStillSorts() {
        let store = RowStore()
        store.apply(.snapshot(queueSnapshot([
            snap(1, sizeBytes: 100),
            snap(2, sizeBytes: nil)
        ])))

        XCTAssertEqual(TablePresentation.cellText(for: store.rows[1], column: .size), "—")

        var config = ColumnConfig.default
        config.sortColumn = .size
        config.sortDirection = .ascending
        store.setColumnConfig(config)
        XCTAssertEqual(store.visibleRows.map { String($0.id.uuidString.suffix(1)) }, ["1", "2"])
    }

    func test_runningStatusOmitsPercentFromPill() {
        let progress = Progress(
            fraction: 0.89,
            speedBytesPerSec: 1_000_000,
            etaSeconds: 38,
            downloadedBytes: 890,
            totalBytes: 1000
        )
        var running = snap(1, state: .running)
        running = JobSnapshot(
            id: running.id,
            url: running.url,
            title: running.title,
            state: .running,
            progress: progress,
            kind: running.kind,
            durationSeconds: running.durationSeconds,
            extractor: running.extractor,
            addedAt: running.addedAt,
            finishedAt: running.finishedAt,
            destFolder: running.destFolder,
            outputFiles: running.outputFiles,
            sizeBytes: running.sizeBytes,
            actualQuality: running.actualQuality,
            attempt: running.attempt,
            cooldownUntil: running.cooldownUntil,
            playerClientUsed: running.playerClientUsed,
            playlistGroupID: running.playlistGroupID,
            integrityVerdict: running.integrityVerdict,
            availableActions: running.availableActions
        )
        let row = RowModel(running, queuePosition: nil)
        XCTAssertEqual(TablePresentation.statusDisplay(for: row), "downloading")
        XCTAssertEqual(TablePresentation.cellText(for: row, column: .progress), "89%")
    }

    func test_actionBarEnabledDisabledPerState() {
        let queued = RowModel(snap(1, state: .queued), queuePosition: 1)
        let completed = RowModel(snap(2, state: .completed), queuePosition: nil)

        for action in RowAction.displayOrder {
            let queuedEnabled = TablePresentation.isActionEnabled(
                action,
                available: queued.snapshot.availableActions
            )
            let completedEnabled = TablePresentation.isActionEnabled(
                action,
                available: completed.snapshot.availableActions
            )
            switch action {
            case .pause, .cancel, .forceStart, .remove, .openInBrowser:
                XCTAssertTrue(queuedEnabled, "\(action)")
            case .reveal:
                XCTAssertTrue(completedEnabled, "\(action)")
                XCTAssertFalse(queuedEnabled, "\(action)")
            case .showLog:
                XCTAssertTrue(completedEnabled, "\(action)")
                XCTAssertFalse(queuedEnabled, "\(action)")
            case .resume, .retry, .retryWithCookies:
                XCTAssertFalse(queuedEnabled, "\(action)")
                XCTAssertFalse(completedEnabled, "\(action)")
            }
        }
    }

    func test_filteredEmptyShowsCorrectLine() {
        let store = RowStore()
        store.apply(.snapshot(queueSnapshot([snap(1, state: .completed)])))
        store.activeChip = .downloading

        let message = TablePresentation.emptyBodyMessage(
            rowCount: store.rows.count,
            visibleCount: store.visibleRows.count,
            activeChip: store.activeChip,
            columnFilters: [:]
        )
        XCTAssertEqual(message, TablePresentation.filteredEmptyMessage)
    }

    func test_emptyQueueShowsCorrectLine() {
        let store = RowStore()
        let message = TablePresentation.emptyBodyMessage(
            rowCount: store.rows.count,
            visibleCount: store.visibleRows.count,
            activeChip: .all,
            columnFilters: [:]
        )
        XCTAssertEqual(message, TablePresentation.emptyQueueMessage)
    }

    func test_columnConfigChangeWithinDebounceThenFlushNow_isWritten() async {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-columns-\(UUID().uuidString)")
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let log = LogWriter(directory: dir.appendingPathComponent("logs"))
        let persistence = Persistence(dir: dir, clock: clock, log: log)
        let fake = FakeQueuePersisting()

        let appModel = AppModel(
            engine: FakeEngine(),
            probe: FakeMetadataProbe(.failure(.malformedOutput)),
            installer: OnboardingInstaller(
                probe: FakeEnvironmentProbe(ready: true),
                runner: NullRunner()
            ),
            prefs: Preferences(),
            log: log,
            persistence: fake
        )

        var config = appModel.columnConfig
        config.sortColumn = .title
        appModel.columnConfig = config

        config.sortColumn = .size
        appModel.columnConfig = config

        XCTAssertEqual(fake.columnSaves.count, 2)
        XCTAssertEqual(fake.columnSaves.last?.sortColumn, .size)

        persistence.saveColumns(config)
        await persistence.flushNow()
        let loaded = persistence.loadColumns()
        XCTAssertEqual(loaded?.sortColumn, .size)

        try? FileManager.default.removeItem(at: dir)
    }
}
