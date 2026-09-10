@testable import GrabberKit
import TestSupport
import XCTest

final class PersistenceGroupTests: XCTestCase {
    private var dir = URL(fileURLWithPath: "/tmp")
    private var clock = FakeClock()

    override func setUp() {
        super.setUp()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-persist-groups-\(UUID().uuidString)")
        clock = FakeClock(now: Date(timeIntervalSince1970: 0))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func test_queueFileRoundTripPreservesGroups() throws {
        let file = QueueFile(
            schemaVersion: 1,
            jobs: [job(1), job(2)],
            groups: [group()]
        )

        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(QueueFile.self, from: data)

        XCTAssertEqual(decoded.jobs, file.jobs)
        XCTAssertEqual(decoded.groups, file.groups)
    }

    func test_queueFileWithoutGroupsDecodesEmptyGroups() throws {
        let json = """
        {
          "schemaVersion": 1,
          "jobs": []
        }
        """

        let decoded = try JSONDecoder().decode(QueueFile.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.groups, [])
    }

    func test_savePlaylistGroupsAfterQueueKeepsQueueJobs() async {
        let persistence = makePersistence()
        let queued = [job(1)]
        let groups = [group()]

        persistence.saveQueue(queued)
        await persistence.flushNow()
        persistence.savePlaylistGroups(groups)
        await persistence.flushNow()

        let restored = makePersistence()
        XCTAssertEqual(restored.loadQueue(), queued)
        XCTAssertEqual(restored.loadPlaylistGroups(), groups)
    }

    func test_saveQueueAfterPlaylistGroupsKeepsPlaylistGroups() async {
        let persistence = makePersistence()
        let queued = [job(1)]
        let groups = [group()]

        persistence.savePlaylistGroups(groups)
        await persistence.flushNow()
        persistence.saveQueue(queued)
        await persistence.flushNow()

        let restored = makePersistence()
        XCTAssertEqual(restored.loadQueue(), queued)
        XCTAssertEqual(restored.loadPlaylistGroups(), groups)
    }

    func test_freshSavePlaylistGroupsKeepsDiskQueueJobs() async throws {
        let queued = [job(1)]
        let originalGroups = [group()]
        let updatedGroups = [group(title: "Updated Collection")]
        try writeQueueFile(jobs: queued, groups: originalGroups)

        let persistence = makePersistence()
        persistence.savePlaylistGroups(updatedGroups)
        await persistence.flushNow()

        let restored = makePersistence()
        XCTAssertEqual(restored.loadQueue(), queued)
        XCTAssertEqual(restored.loadPlaylistGroups(), updatedGroups)
    }

    func test_freshSaveQueueKeepsDiskPlaylistGroups() async throws {
        let originalQueue = [job(1)]
        let updatedQueue = [job(2)]
        let groups = [group()]
        try writeQueueFile(jobs: originalQueue, groups: groups)

        let persistence = makePersistence()
        persistence.saveQueue(updatedQueue)
        await persistence.flushNow()

        let restored = makePersistence()
        XCTAssertEqual(restored.loadQueue(), updatedQueue)
        XCTAssertEqual(restored.loadPlaylistGroups(), groups)
    }

    func test_freshPlaylistGroupSaveThenQueueSaveKeepsUpdatedGroups() async throws {
        let originalQueue = [job(1)]
        let updatedQueue = [job(2)]
        let originalGroups = [group()]
        let updatedGroups = [group(title: "Updated Collection")]
        try writeQueueFile(jobs: originalQueue, groups: originalGroups)

        let persistence = makePersistence()
        persistence.savePlaylistGroups(updatedGroups)
        await persistence.flushNow()
        persistence.saveQueue(updatedQueue)
        await persistence.flushNow()

        let restored = makePersistence()
        XCTAssertEqual(restored.loadQueue(), updatedQueue)
        XCTAssertEqual(restored.loadPlaylistGroups(), updatedGroups)
    }

    func test_freshQueueSaveThenPlaylistGroupSaveKeepsUpdatedQueue() async throws {
        let originalQueue = [job(1)]
        let updatedQueue = [job(2)]
        let originalGroups = [group()]
        let updatedGroups = [group(title: "Updated Collection")]
        try writeQueueFile(jobs: originalQueue, groups: originalGroups)

        let persistence = makePersistence()
        persistence.saveQueue(updatedQueue)
        await persistence.flushNow()
        persistence.savePlaylistGroups(updatedGroups)
        await persistence.flushNow()

        let restored = makePersistence()
        XCTAssertEqual(restored.loadQueue(), updatedQueue)
        XCTAssertEqual(restored.loadPlaylistGroups(), updatedGroups)
    }

    private func makePersistence() -> Persistence {
        Persistence(
            dir: dir,
            clock: clock,
            log: LogWriter(directory: dir.appendingPathComponent("logs"))
        )
    }

    private func writeQueueFile(
        jobs: [PersistedJob],
        groups: [PersistedPlaylistGroup]
    ) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = QueueFile(schemaVersion: 1, jobs: jobs, groups: groups)
        try JSONEncoder().encode(file).write(to: dir.appendingPathComponent("queue.json"))
    }

    private func job(_ index: Int) -> PersistedJob {
        PersistedJob(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")!,
            request: DownloadRequest(
                url: "https://archive.org/details/item-\(index)",
                destFolder: URL(fileURLWithPath: "/tmp/out"),
                kind: .video(maxHeight: 1080),
                container: "mp4",
                filenameTemplate: "%(title)s.%(ext)s"
            ),
            title: "Item \(index)",
            extractor: "archive",
            durationSeconds: 10,
            state: .queued,
            attempt: 0,
            playlistGroupID: nil,
            addedAt: Date(timeIntervalSince1970: TimeInterval(index)),
            finishedAt: nil
        )
    }

    private func group(title: String = "Collection") -> PersistedPlaylistGroup {
        PersistedPlaylistGroup(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            title: title,
            sourceURL: "https://archive.org/details/collection",
            isCollapsed: false
        )
    }
}
