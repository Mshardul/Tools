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
}
