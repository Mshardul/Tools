@testable import GrabberKit
import XCTest

final class YtDlpArgumentsTests: XCTestCase {
    private let dest = URL(fileURLWithPath: "/Users/x/Movies")
    private let url = "https://example.com/watch?v=abc"

    private let progressTemplate = "download:MG|%(progress._percent_str)s|"
        + "%(progress._speed_str)s|%(progress._eta_str)s|"
        + "%(progress.downloaded_bytes)s|%(progress.total_bytes)s"

    private func request(
        kind: DownloadKind,
        container: String? = nil,
        template: String = "%(title)s.%(ext)s"
    ) -> DownloadRequest {
        DownloadRequest(
            url: url,
            destFolder: dest,
            kind: kind,
            container: container,
            outputTemplate: template
        )
    }

    func test_video1080_mp4() {
        let argv = YtDlpArguments.build(for: request(
            kind: .video(maxHeight: 1080),
            container: "mp4"
        ))
        XCTAssertEqual(argv, [
            "-P", "/Users/x/Movies",
            "-o", "%(title)s.%(ext)s",
            "-f",
            "bv*[height<=1080][ext=mp4]+ba[ext=m4a]/bv*[height<=1080]+ba/b[height<=1080]",
            "--merge-output-format", "mp4",
            "--newline", "--progress", "--progress-template", progressTemplate,
            "--no-playlist",
            "--no-warnings",
            url
        ])
    }

    func test_video720_noContainer() {
        let argv = YtDlpArguments.build(for: request(kind: .video(maxHeight: 720)))
        XCTAssertFalse(argv.contains("--merge-output-format"))
        XCTAssertTrue(argv
            .contains("bv*[height<=720][ext=mp4]+ba[ext=m4a]/bv*[height<=720]+ba/b[height<=720]"))
    }

    func test_audio_m4a() {
        let argv = YtDlpArguments.build(for: request(kind: .audio(codec: .m4a)))
        XCTAssertTrue(hasSubsequence(argv, ["-x", "--audio-format", "m4a"]))
    }

    func test_audio_mp3() {
        let argv = YtDlpArguments.build(for: request(kind: .audio(codec: .mp3)))
        XCTAssertTrue(hasSubsequence(argv, ["-x", "--audio-format", "mp3"]))
    }

    func test_customOutputTemplate() throws {
        let argv = YtDlpArguments.build(for: request(
            kind: .video(maxHeight: 1080),
            template: "%(uploader)s - %(title)s.%(ext)s"
        ))
        let index = try XCTUnwrap(argv.firstIndex(of: "-o"))
        XCTAssertEqual(argv[index + 1], "%(uploader)s - %(title)s.%(ext)s")
    }

    func test_urlIsLast() {
        let argv = YtDlpArguments.build(for: request(kind: .audio(codec: .mp3)))
        XCTAssertEqual(argv.last, url)
    }

    func test_progressTemplateIsExact() throws {
        let argv = YtDlpArguments.build(for: request(kind: .video(maxHeight: 1080)))
        let index = try XCTUnwrap(argv.firstIndex(of: "--progress-template"))
        XCTAssertEqual(argv[index + 1], progressTemplate)
    }

    func test_redactedEqualsBuild_phase1() {
        let requests: [DownloadRequest] = [
            request(kind: .video(maxHeight: 1080), container: "mp4"),
            request(kind: .video(maxHeight: 720)),
            request(kind: .audio(codec: .m4a)),
            request(kind: .audio(codec: .mp3)),
            request(kind: .video(maxHeight: 2160), template: "%(id)s.%(ext)s")
        ]
        for req in requests {
            XCTAssertEqual(
                YtDlpArguments.redacted(for: req),
                YtDlpArguments.build(for: req)
            )
        }
    }

    private func hasSubsequence(_ array: [String], _ sub: [String]) -> Bool {
        guard let start = array.firstIndex(of: sub[0]) else { return false }
        guard start + sub.count <= array.count else { return false }
        return Array(array[start ..< start + sub.count]) == sub
    }
}
