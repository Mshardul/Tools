@testable import MediaGrabber
import XCTest

final class AppUpdateCheckerTests: XCTestCase {
    struct FakeGitHubReleaseChecking: GitHubReleaseChecking {
        let result: Result<GitHubRelease, Error>
        func latestRelease(owner _: String, repo _: String) async throws -> GitHubRelease {
            try result.get()
        }
    }

    func testNewerReleaseAvailableReportsUpdateAvailable() async throws {
        let release = try GitHubRelease(
            tagName: "media-grabber-v1.5.0",
            htmlURL: XCTUnwrap(URL(string: "https://github.com/example/repo/releases/tag/media-grabber-v1.5.0"))
        )
        let checker = AppUpdateChecker(client: FakeGitHubReleaseChecking(result: .success(release)))
        let status = await checker.checkForUpdate(currentVersion: "1.4.0")
        XCTAssertEqual(status, .updateAvailable(version: "1.5.0", releaseURL: release.htmlURL))
    }

    func testSameVersionAsCurrentReportsUpToDate() async throws {
        let release = try GitHubRelease(
            tagName: "media-grabber-v1.4.0",
            htmlURL: XCTUnwrap(URL(string: "https://github.com/example/repo/releases/tag/media-grabber-v1.4.0"))
        )
        let checker = AppUpdateChecker(client: FakeGitHubReleaseChecking(result: .success(release)))
        let status = await checker.checkForUpdate(currentVersion: "1.4.0")
        XCTAssertEqual(status, .upToDate)
    }

    func testOlderReleaseThanCurrentReportsUpToDate() async throws {
        let release = try GitHubRelease(
            tagName: "media-grabber-v1.3.0",
            htmlURL: XCTUnwrap(URL(string: "https://github.com/example/repo/releases/tag/media-grabber-v1.3.0"))
        )
        let checker = AppUpdateChecker(client: FakeGitHubReleaseChecking(result: .success(release)))
        let status = await checker.checkForUpdate(currentVersion: "1.4.0")
        XCTAssertEqual(status, .upToDate)
    }

    func testNetworkFailureReportsCheckFailed() async {
        struct NetworkError: Error {}
        let checker = AppUpdateChecker(client: FakeGitHubReleaseChecking(result: .failure(NetworkError())))
        let status = await checker.checkForUpdate(currentVersion: "1.4.0")
        XCTAssertEqual(status, .checkFailed)
    }
}
