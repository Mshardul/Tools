@testable import GrabberKit
import TestSupport
import XCTest

final class PersistenceTests: XCTestCase {
    private var dir = URL(fileURLWithPath: "/tmp")
    private var clock = FakeClock()

    override func setUp() {
        super.setUp()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-persist-\(UUID().uuidString)")
        clock = FakeClock(now: Date(timeIntervalSince1970: 0))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func makePersistence(reset: Bool = false) -> Persistence {
        Persistence(
            dir: dir,
            clock: clock,
            log: LogWriter(directory: dir.appendingPathComponent("logs")),
            debug: PersistenceDebug(resetState: reset)
        )
    }

    private func job(
        _ index: Int,
        state: PersistedState = .queued,
        finishedAt: Date? = nil,
        title: String? = "t",
        extractor: String? = "youtube",
        duration: Int? = 10
    ) -> PersistedJob {
        PersistedJob(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")!,
            request: request(url: "u\(index)"),
            title: title, extractor: extractor, durationSeconds: duration,
            state: state, attempt: 0, playlistGroupID: nil,
            addedAt: Date(timeIntervalSince1970: TimeInterval(index)), finishedAt: finishedAt
        )
    }

    private func request(
        url: String = "https://archive.org/x",
        kind: DownloadKind = .video(maxHeight: 1080),
        container: String? = "mp4",
        template: String = "%(title)s.%(ext)s",
        dest: URL = URL(fileURLWithPath: "/tmp/out")
    ) -> DownloadRequest {
        DownloadRequest(
            url: url,
            destFolder: dest,
            kind: kind,
            container: container,
            filenameTemplate: template
        )
    }

    private func flush(_ persistence: Persistence) async {
        await persistence.flushNow()
    }

    // MARK: - Round-trips

    func test_roundTripQueueFile() throws {
        let file = QueueFile(schemaVersion: 1, jobs: [job(1), job(2)])
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(QueueFile.self, from: data)
        XCTAssertEqual(decoded.jobs, file.jobs)
    }

    func test_roundTripHistoryFile() throws {
        let file = HistoryFile(
            schemaVersion: 1,
            jobs: [job(1, state: .completed, finishedAt: .init())]
        )
        let data = try JSONEncoder().encode(file)
        XCTAssertEqual(try JSONDecoder().decode(HistoryFile.self, from: data).jobs, file.jobs)
    }

    func test_roundTripColumnsFile() throws {
        var config = ColumnConfig.default
        config.sortColumn = .progress
        config.sortDirection = .descending
        config.columnFilters = [.type: ["Video"]]
        let file = ColumnsFile(schemaVersion: 1, config: config)
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(ColumnsFile.self, from: data)
        XCTAssertEqual(decoded.config, config)
    }

    func test_downloadRequestFullRoundTripEquality() throws {
        let deep = URL(fileURLWithPath: "/Users/x/Movies/Archive/2026/clips")
        let requests = [
            request(
                kind: .video(maxHeight: 720),
                container: "mkv",
                template: "%(id)s.%(ext)s",
                dest: deep
            ),
            request(kind: .audio(format: .mp3), container: nil, template: "a/%(title)s.%(ext)s")
        ]
        for original in requests {
            let persisted = PersistedJob(
                id: UUID(), request: original, state: .queued, addedAt: .init()
            )
            let data = try JSONEncoder().encode(persisted)
            let decoded = try JSONDecoder().decode(PersistedJob.self, from: data)
            XCTAssertEqual(decoded.request, original)
        }
    }

    // MARK: - Clamp + restore mapping

    func test_runningAndProbingClampToQueued() {
        XCTAssertEqual(PersistedState.persisted(from: .running), .queued)
        XCTAssertEqual(PersistedState.persisted(from: .probing), .queued)
        XCTAssertEqual(PersistedState.persisted(from: .waitingForNetwork), .queued)
        XCTAssertEqual(PersistedState.persisted(from: .cooldown(until: .init())), .queued)
    }

    func test_restoredFailedJob_becomesUnknownRaw() {
        let state = PersistedState.failed(reason: "boom").restoredJobState
        guard case let .failed(.unknown(raw)) = state else {
            return XCTFail("expected .failed(.unknown)")
        }
        XCTAssertEqual(raw, "boom")
    }

    // MARK: - Order

    func test_queueOrderPreservedOnRestore() async {
        let persistence = makePersistence()
        let outOfOrder = [job(3), job(1), job(2)]
        persistence.saveQueue(outOfOrder)
        await flush(persistence)

        let loaded = makePersistence().loadQueue()
        XCTAssertEqual(loaded.map(\.id), outOfOrder.map(\.id))
    }

    // MARK: - Load table

    func test_corruptJSON_startsEmpty_logsCorrupt_noThrow() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: dir.appendingPathComponent("queue.json"))
        XCTAssertEqual(makePersistence().loadQueue().count, 0)
    }

    func test_schemaAhead_startsEmpty_doesNotParse() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ahead = QueueFile(schemaVersion: 99, jobs: [job(1)])
        try JSONEncoder().encode(ahead).write(to: dir.appendingPathComponent("queue.json"))
        XCTAssertEqual(makePersistence().loadQueue().count, 0)
    }

    func test_fileAbsent_startsEmpty() {
        XCTAssertEqual(makePersistence().loadQueue().count, 0)
        XCTAssertNil(makePersistence().loadColumns())
    }

    func test_debugResetState_noLoads() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(QueueFile(schemaVersion: 1, jobs: [job(1)]))
            .write(to: dir.appendingPathComponent("queue.json"))
        XCTAssertEqual(makePersistence(reset: true).loadQueue().count, 0)
    }

    // MARK: - History cap

    func test_historyCapAt200() async {
        let persistence = makePersistence()
        let jobs = (0 ..< 201).map {
            job(
                $0 % 10,
                state: .completed,
                finishedAt: Date(timeIntervalSince1970: TimeInterval($0))
            )
        }
        persistence.saveHistory(jobs)
        await flush(persistence)

        let loaded = makePersistence().loadHistory()
        XCTAssertEqual(loaded.count, 200)
        // The oldest finishedAt (index 0) is the one dropped.
        XCTAssertFalse(loaded.contains { $0.finishedAt == Date(timeIntervalSince1970: 0) })
    }

    // MARK: - Debounce / skip

    func test_changeWithinDebounceThenFlushNow_isWritten() async {
        let persistence = makePersistence()
        persistence.saveQueue([job(1)])
        // Do not advance the clock past the 500 ms debounce.
        await flush(persistence)
        XCTAssertEqual(makePersistence().loadQueue().map(\.id), [job(1).id])
    }

    func test_identicalProjection_noSecondWrite() async throws {
        let persistence = makePersistence()
        persistence.saveQueue([job(1)])
        await flush(persistence)
        let url = dir.appendingPathComponent("queue.json")
        let firstModified = try FileManager.default
            .attributesOfItem(atPath: url.path)[.modificationDate] as? Date

        try await Task.sleep(for: .milliseconds(20))
        persistence.saveQueue([job(1)])
        await flush(persistence)
        let secondModified = try FileManager.default
            .attributesOfItem(atPath: url.path)[.modificationDate] as? Date

        XCTAssertEqual(firstModified, secondModified)
    }

    // MARK: - Columns lenient decode

    func test_columnsUnknownColumnDropped() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = """
        { "schemaVersion": 1, "config": {
          "visibleColumns": ["title", "bogus", "status"],
          "columnOrder": ["title", "status", "actions"],
          "columnFilters": {}
        }}
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("columns.json"))
        let config = try XCTUnwrap(makePersistence().loadColumns())
        XCTAssertFalse(config.visibleColumns.map(\.rawValue).contains("bogus"))
        XCTAssertTrue(config.visibleColumns.contains(.title))
    }

    func test_columnsMissingKnownColumnAppended() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = """
        { "schemaVersion": 1, "config": {
          "visibleColumns": ["title", "actions"],
          "columnOrder": ["title", "actions"],
          "columnFilters": {}
        }}
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("columns.json"))
        let config = try XCTUnwrap(makePersistence().loadColumns())
        XCTAssertTrue(config.columnOrder.contains(.status))
        XCTAssertEqual(config.columnOrder.last, .actions)
    }

    // MARK: - Write failure

    func test_writeThrow_thenSuccess_recovers() async throws {
        // Point the persistence dir at a path whose parent is a file → createDirectory fails.
        let blocker = dir.appendingPathComponent("blocker")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: blocker)
        let badPersistence = Persistence(
            dir: blocker.appendingPathComponent("sub"),
            clock: clock,
            log: LogWriter(directory: dir.appendingPathComponent("logs"))
        )
        badPersistence.saveQueue([job(1)])
        await badPersistence.flushNow()
        let failed = await badPersistence.didFirstWriteFail
        XCTAssertTrue(failed)

        try FileManager.default.removeItem(at: blocker)
        badPersistence.saveQueue([job(2)])
        await badPersistence.flushNow()
        let recovered = await badPersistence.didFirstWriteFail
        XCTAssertFalse(recovered)
    }
}
