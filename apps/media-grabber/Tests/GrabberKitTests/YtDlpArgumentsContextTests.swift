@testable import GrabberKit
import XCTest

final class YtDlpArgumentsContextTests: XCTestCase {
    private let dest = URL(fileURLWithPath: "/Users/x/Movies")
    private let url = "https://example.com/watch?v=abc"

    private func request(kind: DownloadKind) -> DownloadRequest {
        DownloadRequest(
            url: url,
            destFolder: dest,
            kind: kind,
            filenameTemplate: "%(title)s.%(ext)s"
        )
    }

    private func potURL() throws -> URL {
        try XCTUnwrap(URL(string: "http://127.0.0.1:4416"))
    }

    func testContextEmitsPluginDirsPotAndClient() throws {
        let pot = try potURL()
        let ctx = ExtractorContext(
            pluginDirs: [URL(fileURLWithPath: "/tmp/plug")],
            potBaseURL: pot,
            playerClient: "tv",
            cookieArgument: nil
        )
        let argv = YtDlpArguments.build(
            for: request(kind: .video(maxHeight: 1080)),
            context: ctx,
            concurrentFragments: 4
        )
        XCTAssertTrue(argv.contains("--plugin-dirs"))
        XCTAssertTrue(argv.contains("/tmp/plug"))
        XCTAssertTrue(argv.contains("youtubepot-bgutilhttp:base_url=http://127.0.0.1:4416"))
        XCTAssertTrue(argv.contains("youtube:player_client=tv"))
    }

    func testNoneContextDoesNotEmitExtractorArgs() {
        let argv = YtDlpArguments.build(
            for: request(kind: .video(maxHeight: 1080)),
            concurrentFragments: 4
        )
        XCTAssertFalse(argv.contains("--plugin-dirs"))
        XCTAssertFalse(argv.contains(where: { $0.contains("player_client") }))
    }

    func testRedactedKeepsPotAndClient() throws {
        let pot = try potURL()
        let ctx = ExtractorContext(
            pluginDirs: [],
            potBaseURL: pot,
            playerClient: "ios",
            cookieArgument: "safari"
        )
        let red = YtDlpArguments.redacted(
            for: request(kind: .video(maxHeight: 720)),
            cookieArgument: "safari",
            context: ctx,
            concurrentFragments: 4
        )
        XCTAssertTrue(red.contains("<redacted>"))
        XCTAssertTrue(red.contains("youtube:player_client=ios"))
        XCTAssertTrue(red.contains("youtubepot-bgutilhttp:base_url=http://127.0.0.1:4416"))
    }

    func testRedactedEqualsBuildWithContext() throws {
        let pot = try potURL()
        let ctx = ExtractorContext(
            pluginDirs: [URL(fileURLWithPath: "/tmp/plug")],
            potBaseURL: pot,
            playerClient: "tv",
            cookieArgument: nil
        )
        let req = request(kind: .video(maxHeight: 1080))
        XCTAssertEqual(
            YtDlpArguments.redacted(for: req, context: ctx, concurrentFragments: 4),
            YtDlpArguments.build(for: req, context: ctx, concurrentFragments: 4)
        )
    }
}
