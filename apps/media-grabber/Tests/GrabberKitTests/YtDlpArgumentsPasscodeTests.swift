@testable import GrabberKit
import XCTest

final class YtDlpArgumentsPasscodeTests: XCTestCase {
    private func request() -> DownloadRequest {
        DownloadRequest(
            url: "https://example.zoom.us/rec/share/abc",
            destFolder: URL(fileURLWithPath: "/tmp/out"),
            kind: .video(maxHeight: 1080),
            container: "mp4"
        )
    }

    private func context(_ passcode: String?) -> ExtractorContext {
        ExtractorContext(
            pluginDirs: [],
            potBaseURL: nil,
            playerClient: nil,
            cookieArgument: nil,
            videoPassword: passcode
        )
    }

    func test_videoPasswordEmittedAsSingleToken() {
        let argv = YtDlpArguments.build(for: request(), context: context("-abc d"), concurrentFragments: 4)
        XCTAssertTrue(argv.contains("--video-password=-abc d"))
        XCTAssertFalse(argv.contains("--video-password"))
        XCTAssertFalse(argv.contains("-abc d"))
    }

    func test_redactedMasksVideoPassword() {
        let argv = YtDlpArguments.redacted(for: request(), context: context("-abc d"), concurrentFragments: 4)
        XCTAssertTrue(argv.contains("--video-password=<redacted>"))
        XCTAssertFalse(argv.contains { $0.contains("abc d") })
    }

    func test_noPasswordEmitsNoFlag() {
        for passcode in [nil, ""] {
            let argv = YtDlpArguments.build(
                for: request(), context: context(passcode), concurrentFragments: 4
            )
            let hasFlag = argv.contains { $0.hasPrefix("--video-password") }
            XCTAssertFalse(hasFlag, "passcode: \(String(describing: passcode))")
        }
    }
}
