@testable import GrabberKit
import TestSupport
import XCTest

final class PersistenceDisableWritesTests: XCTestCase {
    private var dir = URL(fileURLWithPath: "/tmp")

    override func setUp() {
        super.setUp()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-disable-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func makePersistence() -> Persistence {
        Persistence(
            dir: dir,
            clock: FakeClock(now: Date(timeIntervalSince1970: 0)),
            log: LogWriter(directory: dir.appendingPathComponent("logs"))
        )
    }

    private func job() -> PersistedJob {
        PersistedJob(
            id: UUID(),
            request: DownloadRequest(
                url: "https://archive.org/x",
                destFolder: URL(fileURLWithPath: "/tmp/out"),
                kind: .video(maxHeight: 1080),
                container: "mp4",
                filenameTemplate: "%(title)s.%(ext)s"
            ),
            title: "t", extractor: "youtube", durationSeconds: 10,
            state: .queued, attempt: 0, playlistGroupID: nil,
            addedAt: Date(timeIntervalSince1970: 0), finishedAt: nil
        )
    }

    func test_disableWrites_flushAfterwardsWritesNothing() async {
        let persistence = makePersistence()
        persistence.saveQueue([job()])
        persistence.disableWrites()
        await persistence.flushNow()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("queue.json").path))
    }

    func test_disableWrites_savesAfterwardsAreIgnored() async {
        let persistence = makePersistence()
        persistence.disableWrites()
        persistence.saveQueue([job()])
        persistence.saveHistory([job()])
        persistence.saveColumns(ColumnConfig.default)
        await persistence.flushNow()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }
}
