@testable import GrabberKit
import XCTest

final class ManagedToolsTests: XCTestCase {
    func test_paths_stayInsideTheBundleAndSupportFolder() {
        let tools = ManagedTools(
            resourceRoot: URL(fileURLWithPath: "/Apps/MediaGrabber.app/Contents/Resources"),
            supportRoot: URL(fileURLWithPath: "/Users/tester/Library/Application Support/MediaGrabber"),
            isExecutable: { _ in false }
        )
        XCTAssertEqual(tools.bundledYtDlp.lastPathComponent, "yt-dlp")
        XCTAssertTrue(tools.bundledYtDlp.path.contains("/Resources/Tools/"))
        XCTAssertTrue(tools.ffmpegURL.path.hasSuffix("/Resources/Tools/ffmpeg"))
        XCTAssertTrue(tools.ffprobeURL.path.hasSuffix("/Resources/Tools/ffprobe"))
        XCTAssertTrue(tools.nodeURL.path.hasSuffix("/Resources/Tools/node"))
        XCTAssertTrue(tools.updatedYtDlp.path.hasSuffix("/MediaGrabber/bin/yt-dlp"))
        XCTAssertTrue(tools.shieldServer.path.hasSuffix("/Resources/Shield/server/build/main.js"))
        XCTAssertTrue(tools.shieldPlugin.path.hasSuffix("/Resources/Shield/plugin.zip"))
    }

    func test_ytDlp_usesTheBundledCopyWhenNothingNewerExists() {
        let bundled = URL(fileURLWithPath: "/bundle/Tools/yt-dlp")
        let tools = ManagedTools(
            resourceRoot: URL(fileURLWithPath: "/bundle"),
            supportRoot: URL(fileURLWithPath: "/support"),
            isExecutable: { $0 == bundled }
        )
        XCTAssertEqual(tools.ytDlpURL(), bundled)
    }

    private let bundled = URL(fileURLWithPath: "/bundle/Tools/yt-dlp")
    private let updated = URL(fileURLWithPath: "/support/bin/yt-dlp")

    private func tools(
        executable: Set<URL>,
        versions: [URL: String]
    ) -> ManagedTools {
        ManagedTools(
            resourceRoot: URL(fileURLWithPath: "/bundle"),
            supportRoot: URL(fileURLWithPath: "/support"),
            isExecutable: { executable.contains($0) },
            versionOf: { versions[$0] }
        )
    }

    func test_ytDlp_updatedNewer_wins() {
        let sut = tools(executable: [bundled, updated], versions: [bundled: "2026.05.01", updated: "2026.08.01"])
        XCTAssertEqual(sut.ytDlpURL(), updated)
    }

    func test_ytDlp_updatedOlder_bundledWins() {
        let sut = tools(executable: [bundled, updated], versions: [bundled: "2026.08.01", updated: "2026.05.01"])
        XCTAssertEqual(sut.ytDlpURL(), bundled)
    }

    func test_ytDlp_updatedEqual_bundledWins() {
        let sut = tools(executable: [bundled, updated], versions: [bundled: "2026.08.01", updated: "2026.08.01"])
        XCTAssertEqual(sut.ytDlpURL(), bundled)
    }

    func test_ytDlp_updatedNotExecutable_bundledWins() {
        let sut = tools(executable: [bundled], versions: [bundled: "2026.05.01", updated: "2026.08.01"])
        XCTAssertEqual(sut.ytDlpURL(), bundled)
    }

    func test_ytDlp_updatedUnreadableVersion_bundledWins() {
        let sut = tools(executable: [bundled, updated], versions: [bundled: "2026.05.01"])
        XCTAssertEqual(sut.ytDlpURL(), bundled)
    }

    func test_ytDlp_bundledMissing_updatedIsUsed() {
        let sut = tools(executable: [updated], versions: [updated: "2026.08.01"])
        XCTAssertEqual(sut.ytDlpURL(), updated)
    }

    func test_ffmpeg_ignoresSupportDirectory() {
        let sut = tools(executable: [], versions: [:])
        XCTAssertFalse(sut.ffmpegURL.path.hasPrefix("/support"))
        XCTAssertFalse(sut.ffprobeURL.path.hasPrefix("/support"))
        XCTAssertFalse(sut.nodeURL.path.hasPrefix("/support"))
    }
}
