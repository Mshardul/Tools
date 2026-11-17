import CryptoKit
@testable import GrabberKit
import TestSupport
import XCTest

final class YtDlpUpdaterTests: XCTestCase {
    private struct FakeFetcher: YtDlpReleaseFetching {
        let result: Result<YtDlpBinary, YtDlpFetchError>
        let downloads: LockedCounter

        init(result: Result<YtDlpBinary, YtDlpFetchError>, downloads: LockedCounter = LockedCounter()) {
            self.result = result
            self.downloads = downloads
        }

        func latestVersion() async -> Result<String, YtDlpFetchError> {
            result.map(\.version)
        }

        func latest() async -> Result<YtDlpBinary, YtDlpFetchError> {
            downloads.increment()
            return result
        }
    }

    private final class LockedCounter: Sendable {
        private let box = LockedBox(0)

        func increment() {
            box.mutate { $0 += 1 }
        }

        var count: Int {
            box.read { $0 }
        }
    }

    private func binary(version: String, bytes: Data, checksum: String? = nil) -> YtDlpBinary {
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return YtDlpBinary(version: version, bytes: bytes, sha256Hex: checksum ?? digest)
    }

    func test_installsWhenChecksumAndCanaryPass() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bytes = Data("downloader".utf8)
        let updater = YtDlpUpdater(
            fetcher: FakeFetcher(result: .success(binary(version: "2026.08.01", bytes: bytes))),
            binDirectory: root,
            minimumVersion: "2026.01.01",
            canary: { _ in true }
        )
        let result = await updater.updateToLatest()
        XCTAssertEqual(result, .success(newVersion: "2026.08.01"))
        let installed = try Data(contentsOf: root.appendingPathComponent("yt-dlp"))
        XCTAssertEqual(installed, bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("yt-dlp.incoming").path))
    }

    func test_checksumMismatch_leavesThePreviousCopy() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let previous = root.appendingPathComponent("yt-dlp")
        try Data("old".utf8).write(to: previous)
        let updater = YtDlpUpdater(
            fetcher: FakeFetcher(result: .success(binary(
                version: "2026.08.01",
                bytes: Data("new".utf8),
                checksum: "deadbeef"
            ))),
            binDirectory: root,
            canary: { _ in true }
        )
        let result = await updater.updateToLatest()
        guard case .failure = result else {
            XCTFail("expected failure, got \(result)")
            return
        }
        let kept = try Data(contentsOf: previous)
        XCTAssertEqual(kept, Data("old".utf8))
    }

    func test_networkFailure_leavesThePreviousCopy() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let previous = root.appendingPathComponent("yt-dlp")
        try Data("old".utf8).write(to: previous)
        let updater = YtDlpUpdater(
            fetcher: FakeFetcher(result: .failure(YtDlpFetchError(message: YtDlpUpdateCopy.offline))),
            binDirectory: root,
            canary: { _ in true }
        )
        let result = await updater.updateToLatest()
        XCTAssertEqual(result, .failure(reason: YtDlpUpdateCopy.offline))
        let kept = try Data(contentsOf: previous)
        XCTAssertEqual(kept, Data("old".utf8))
    }

    func test_canaryFailure_deletesTheIncomingCopy() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let previous = root.appendingPathComponent("yt-dlp")
        try Data("old".utf8).write(to: previous)
        let updater = YtDlpUpdater(
            fetcher: FakeFetcher(result: .success(binary(version: "2026.08.01", bytes: Data("new".utf8)))),
            binDirectory: root,
            minimumVersion: "2026.01.01",
            canary: { _ in false }
        )
        let result = await updater.updateToLatest()
        guard case .failure = result else {
            XCTFail("expected failure, got \(result)")
            return
        }
        let kept = try Data(contentsOf: previous)
        XCTAssertEqual(kept, Data("old".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("yt-dlp.incoming").path))
    }

    func test_alreadyCurrent_returnsSuccessWithoutDownloading() async {
        let downloads = LockedCounter()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let updater = YtDlpUpdater(
            fetcher: FakeFetcher(
                result: .success(binary(version: "2026.08.01", bytes: Data("x".utf8))),
                downloads: downloads
            ),
            binDirectory: root,
            installedVersion: { "2026.08.01" },
            canary: { _ in true }
        )
        let result = await updater.updateToLatest()
        XCTAssertEqual(result, .success(newVersion: "2026.08.01"))
        XCTAssertEqual(downloads.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func test_olderInstalled_downloadsTheNewerOne() async {
        let downloads = LockedCounter()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let updater = YtDlpUpdater(
            fetcher: FakeFetcher(
                result: .success(binary(version: "2026.08.01", bytes: Data("x".utf8))),
                downloads: downloads
            ),
            binDirectory: root,
            minimumVersion: "2026.01.01",
            installedVersion: { "2026.05.01" },
            canary: { _ in true }
        )
        let result = await updater.updateToLatest()
        XCTAssertEqual(result, .success(newVersion: "2026.08.01"))
        XCTAssertEqual(downloads.count, 1)
    }

    func test_truncatedDownload_keepsPreviousCopy_andNeverRunsThePartialFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let previous = root.appendingPathComponent("yt-dlp")
        try Data("old".utf8).write(to: previous)
        let full = Data("a complete downloader".utf8)
        let truncated = full.prefix(5)
        let ran = LockedCounter()
        let updater = YtDlpUpdater(
            fetcher: FakeFetcher(result: .success(YtDlpBinary(
                version: "2026.08.01",
                bytes: Data(truncated),
                sha256Hex: SHA256.hash(data: full).map { String(format: "%02x", $0) }.joined()
            ))),
            binDirectory: root,
            minimumVersion: "2026.01.01",
            canary: { _ in
                ran.increment()
                return true
            }
        )
        let result = await updater.updateToLatest()
        XCTAssertEqual(result, .failure(reason: YtDlpUpdateCopy.damaged))
        XCTAssertEqual(ran.count, 0)
        XCTAssertEqual(try Data(contentsOf: previous), Data("old".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["yt-dlp"])
    }

    func test_installIsAtomic_canaryRunsOnTheIncomingFile_notTheLiveOne() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let previous = root.appendingPathComponent("yt-dlp")
        try Data("old".utf8).write(to: previous)
        let seen = LockedPaths()
        let updater = YtDlpUpdater(
            fetcher: FakeFetcher(result: .success(binary(version: "2026.08.01", bytes: Data("new".utf8)))),
            binDirectory: root,
            minimumVersion: "2026.01.01",
            canary: { url in
                seen.add(url.lastPathComponent)
                return true
            }
        )
        _ = await updater.updateToLatest()
        XCTAssertEqual(seen.values, ["yt-dlp.incoming"])
        XCTAssertEqual(try Data(contentsOf: previous), Data("new".utf8))
    }

    private final class LockedPaths: Sendable {
        private let box = LockedBox<[String]>([])

        func add(_ value: String) {
            box.mutate { $0.append(value) }
        }

        var values: [String] {
            box.read { $0 }
        }
    }
}
