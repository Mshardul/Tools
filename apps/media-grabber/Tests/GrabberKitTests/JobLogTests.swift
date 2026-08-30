@testable import GrabberKit
import TestSupport
import XCTest

final class JobLogTests: XCTestCase {
    private var dir = URL(fileURLWithPath: "/tmp")

    override func setUp() {
        super.setUp()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-joblog-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func request(url: String = "https://archive.org/details/x") -> DownloadRequest {
        DownloadRequest(
            url: url,
            destFolder: URL(fileURLWithPath: "/tmp/out"),
            kind: .video(maxHeight: 1080),
            container: "mp4"
        )
    }

    private func contents(_ id: UUID) throws -> String {
        let url = dir.appendingPathComponent("\(id.uuidString).log")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func test_fakeRun_fileHasHeaderThenStreamedLines() throws {
        let id = UUID()
        let log = JobLog(id: id, request: request(), ytDlpVersion: "2025.01.01", dir: dir)
        try log.writeHeader()
        log.append(.stdout("frame 1"))
        log.append(.stderr("a warning"))
        log.append(.stdout("frame 2"))
        log.close()

        let text = try contents(id)
        XCTAssertTrue(text.contains("yt-dlp: 2025.01.01"))
        XCTAssertTrue(text.contains("url: https://archive.org/details/x"))
        let headerEnd = try XCTUnwrap(text.range(of: "----\n"))
        let body = String(text[headerEnd.upperBound...])
        XCTAssertEqual(
            body.split(separator: "\n", omittingEmptySubsequences: true).map(String.init),
            ["frame 1", "[stderr] a warning", "frame 2"]
        )
    }

    func test_redactionApplied() throws {
        let id = UUID()
        let log = JobLog(id: id, request: request(), ytDlpVersion: "0", dir: dir)
        try log.writeHeader()
        log.append(.stdout("saving to /Users/alice/Movies/x"))
        log.append(.stdout("fetching https://user:pass@host/path"))
        log.close()

        let text = try contents(id)
        XCTAssertTrue(text.contains("~/Movies/x"))
        XCTAssertFalse(text.contains("/Users/alice"))
        XCTAssertTrue(text.contains("https://host/path"))
        XCTAssertFalse(text.contains("user:pass"))
    }

    func test_removeDeletesIt() throws {
        let id = UUID()
        let log = JobLog(id: id, request: request(), ytDlpVersion: "0", dir: dir)
        try log.writeHeader()
        log.close()
        let path = dir.appendingPathComponent("\(id.uuidString).log").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        JobLog.delete(id: id, dir: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func test_capEvictsOldestByFinishedAt() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var jobs: [(id: UUID, finishedAt: Date?)] = []
        for index in 0 ..< 201 {
            let id = UUID()
            jobs.append((id: id, finishedAt: Date(timeIntervalSince1970: TimeInterval(index))))
            try Data("x".utf8).write(to: dir.appendingPathComponent("\(id.uuidString).log"))
        }
        let oldest = try XCTUnwrap(jobs.first)

        JobLog.evict(keepingNewestByFinishedAt: jobs, limit: 200, dir: dir)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(remaining.count, 200)
        XCTAssertFalse(remaining.contains("\(oldest.id.uuidString).log"))
    }
}
