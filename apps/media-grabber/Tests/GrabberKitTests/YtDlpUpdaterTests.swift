import CryptoKit
@testable import GrabberKit
import XCTest

final class YtDlpUpdaterTests: XCTestCase {
    private struct FakeFetcher: YtDlpReleaseFetching {
        let result: Result<YtDlpBinary, YtDlpFetchError>
        func latest() async -> Result<YtDlpBinary, YtDlpFetchError> {
            result
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
        let result = await updater.reinstallToMinimum()
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
        let result = await updater.reinstallToMinimum()
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
            fetcher: FakeFetcher(result: .failure(YtDlpFetchError(message: "The download didn't finish."))),
            binDirectory: root,
            canary: { _ in true }
        )
        let result = await updater.reinstallToMinimum()
        XCTAssertEqual(result, .failure(reason: "The download didn't finish."))
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
        let result = await updater.reinstallToMinimum()
        guard case .failure = result else {
            XCTFail("expected failure, got \(result)")
            return
        }
        let kept = try Data(contentsOf: previous)
        XCTAssertEqual(kept, Data("old".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("yt-dlp.incoming").path))
    }
}
