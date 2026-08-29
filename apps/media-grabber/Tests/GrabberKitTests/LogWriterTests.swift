@testable import GrabberKit
import XCTest

final class LogWriterTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-logs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var logFile: URL {
        directory.appendingPathComponent("app.log")
    }

    private func lines() throws -> [String] {
        guard FileManager.default.fileExists(atPath: logFile.path) else { return [] }
        return try String(contentsOf: logFile, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private func firstFields() throws -> [String: String] {
        let text = try XCTUnwrap(try lines().first)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        return try XCTUnwrap(object["fields"] as? [String: String])
    }

    private func writer(minLevel: LogLevel = .info) -> LogWriter {
        LogWriter(
            directory: directory,
            minLevel: minLevel,
            clock: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    func test_writesJSONLine_perEvent() async throws {
        await writer().log(.appLaunched)

        let all = try lines()
        XCTAssertEqual(all.count, 1)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(all[0].utf8)) as? [String: Any]
        )
        XCTAssertNotNil(object["ts"])
        XCTAssertEqual(object["level"] as? String, "info")
        XCTAssertEqual(object["category"] as? String, "ui")
        XCTAssertEqual(object["event"] as? String, "app.launched")
    }

    func test_belowMinLevel_notWritten() async throws {
        await writer(minLevel: .info).log(.appLaunched, level: .debug)
        XCTAssertEqual(try lines().count, 0)
    }

    func test_redactsUserPath() async throws {
        await writer().log(.processLaunched(
            executable: "/Users/alice/bin/yt-dlp",
            argvRedacted: ["-P", "/Users/alice/Movies", "https://x/y"]
        ))

        let fields = try firstFields()
        XCTAssertEqual(fields["argv"], "-P ~/Movies https://x/y")
        XCTAssertEqual(fields["executable"], "~/bin/yt-dlp")
    }

    func test_redactsCredentials() async throws {
        await writer().log(.probeCompleted(
            url: "http://user:secret@proxy.example.com",
            title: nil,
            ok: true
        ))

        let fields = try firstFields()
        XCTAssertEqual(fields["url"], "http://proxy.example.com")
    }

    func test_rotation() async throws {
        let sut = writer()
        let bigTitle = String(repeating: "x", count: 4096)
        for _ in 0 ..< 1600 {
            await sut.log(.probeCompleted(url: "https://x/y", title: bigTitle, ok: true))
        }

        let rotated = directory.appendingPathComponent("app.log.1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rotated.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: logFile.path))

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("app.log") }
        XCTAssertLessThanOrEqual(files.count, 5)
    }

    func test_concurrentWrites_noInterleaving() async throws {
        let sut = writer()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 100 {
                group.addTask { await sut.log(.appLaunched) }
            }
        }

        let all = try lines()
        XCTAssertEqual(all.count, 100)
        for line in all {
            XCTAssertNoThrow(
                try JSONSerialization.jsonObject(with: Data(line.utf8))
            )
        }
    }
}
