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
            filenameTemplate: template
        )
    }

    private let resilienceFlags = [
        "--retries", "3",
        "--fragment-retries", "10",
        "--socket-timeout", "30",
        "--retry-sleep", "linear=1:10:2",
        "--throttled-rate", "100K",
        "--file-access-retries", "5",
        "--no-part-hint",
        "--sleep-requests", "1",
        "--sleep-interval", "1",
        "--max-sleep-interval", "5"
    ]

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
            "--no-warnings"
        ] + resilienceFlags + [url])
    }

    func test_alwaysOnResilienceFlagsFromDefaultTuning() {
        let argv = YtDlpArguments.build(for: request(
            kind: .video(maxHeight: 1080),
            container: "mp4"
        ))
        XCTAssertTrue(
            hasSubsequence(argv, resilienceFlags),
            "argv missing resilience flags: \(argv)"
        )
        XCTAssertFalse(argv.contains("infinite"))
        let retriesIndex = try? XCTUnwrap(argv.firstIndex(of: "--retries"))
        let urlIndex = try? XCTUnwrap(argv.firstIndex(of: url))
        XCTAssertNotNil(retriesIndex)
        XCTAssertNotNil(urlIndex)
        if let retriesIndex, let urlIndex {
            XCTAssertLessThan(retriesIndex, urlIndex)
        }
    }

    func test_nonDefaultTuningChangesEmittedValues() throws {
        var tuning = YtDlpTuning.default
        tuning.retries = 9
        tuning.throttledRateKBps = 250
        let argv = YtDlpArguments.build(for: request(kind: .video(maxHeight: 720)), tuning: tuning)
        let retriesIndex = try XCTUnwrap(argv.firstIndex(of: "--retries"))
        XCTAssertEqual(argv[retriesIndex + 1], "9")
        let rateIndex = try XCTUnwrap(argv.firstIndex(of: "--throttled-rate"))
        XCTAssertEqual(argv[rateIndex + 1], "250K")
    }

    func test_video720_noContainer() {
        let argv = YtDlpArguments.build(for: request(kind: .video(maxHeight: 720)))
        XCTAssertFalse(argv.contains("--merge-output-format"))
        XCTAssertTrue(argv
            .contains("bv*[height<=720][ext=mp4]+ba[ext=m4a]/bv*[height<=720]+ba/b[height<=720]"))
    }

    func test_audio_m4a() {
        let argv = YtDlpArguments.build(for: request(kind: .audio(format: .m4a)))
        XCTAssertTrue(hasSubsequence(argv, ["-x", "--audio-format", "m4a"]))
    }

    func test_audio_mp3() {
        let argv = YtDlpArguments.build(for: request(kind: .audio(format: .mp3)))
        XCTAssertTrue(hasSubsequence(argv, ["-x", "--audio-format", "mp3"]))
    }

    func test_customFilenameTemplate() throws {
        let argv = YtDlpArguments.build(for: request(
            kind: .video(maxHeight: 1080),
            template: "%(uploader)s - %(title)s.%(ext)s"
        ))
        let index = try XCTUnwrap(argv.firstIndex(of: "-o"))
        XCTAssertEqual(argv[index + 1], "%(uploader)s - %(title)s.%(ext)s")
    }

    func test_urlIsLast() {
        let argv = YtDlpArguments.build(for: request(kind: .audio(format: .mp3)))
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
            request(kind: .audio(format: .m4a)),
            request(kind: .audio(format: .mp3)),
            request(kind: .video(maxHeight: 2160), template: "%(id)s.%(ext)s")
        ]
        for req in requests {
            XCTAssertEqual(
                YtDlpArguments.redacted(for: req),
                YtDlpArguments.build(for: req)
            )
        }
    }

    func test_options_none_noGlobalFlags() {
        let argv = YtDlpArguments.build(for: request(kind: .video(maxHeight: 1080)))
        XCTAssertFalse(argv.contains("--proxy"))
        XCTAssertFalse(argv.contains("-4"))
        XCTAssertFalse(argv.contains("--limit-rate"))
    }

    func test_options_proxy() {
        let options = GlobalDownloadOptions(
            proxyURL: "http://host:8080",
            forceIPv4: false,
            speedLimitKBps: 0
        )
        XCTAssertTrue(hasSubsequence(
            YtDlpArguments.build(for: request(kind: .audio(format: .m4a)), options: options),
            ["--proxy", "http://host:8080"]
        ))
    }

    func test_options_forceIPv4() {
        let options = GlobalDownloadOptions(proxyURL: nil, forceIPv4: true, speedLimitKBps: 0)
        XCTAssertTrue(YtDlpArguments
            .build(for: request(kind: .audio(format: .m4a)), options: options)
            .contains("-4"))
    }

    func test_options_speedLimit() {
        let options = GlobalDownloadOptions(proxyURL: nil, forceIPv4: false, speedLimitKBps: 500)
        XCTAssertTrue(hasSubsequence(
            YtDlpArguments.build(for: request(kind: .audio(format: .m4a)), options: options),
            ["--limit-rate", "500K"]
        ))
    }

    func test_options_speedLimit_zeroOmitsFlag() {
        let options = GlobalDownloadOptions(proxyURL: nil, forceIPv4: false, speedLimitKBps: 0)
        XCTAssertFalse(YtDlpArguments
            .build(for: request(kind: .audio(format: .m4a)), options: options)
            .contains("--limit-rate"))
    }

    func test_redacted_masksProxyUserinfo() throws {
        let options = GlobalDownloadOptions(
            proxyURL: "http://user:secret@host:8080",
            forceIPv4: false,
            speedLimitKBps: 0
        )
        let argv = YtDlpArguments.redacted(
            for: request(kind: .audio(format: .m4a)),
            options: options
        )
        let index = try XCTUnwrap(argv.firstIndex(of: "--proxy"))
        XCTAssertFalse(argv[index + 1].contains("secret"))
        XCTAssertFalse(argv[index + 1].contains("user:"))
        XCTAssertTrue(argv[index + 1].contains("host:8080"))
    }

    func test_redacted_identicalWhenNoProxyCreds() {
        let options = GlobalDownloadOptions(
            proxyURL: "http://host:8080",
            forceIPv4: true,
            speedLimitKBps: 200
        )
        XCTAssertEqual(
            YtDlpArguments.redacted(for: request(kind: .video(maxHeight: 720)), options: options),
            YtDlpArguments.build(for: request(kind: .video(maxHeight: 720)), options: options)
        )
    }

    private func hasSubsequence(_ array: [String], _ sub: [String]) -> Bool {
        guard let start = array.firstIndex(of: sub[0]) else { return false }
        guard start + sub.count <= array.count else { return false }
        return Array(array[start ..< start + sub.count]) == sub
    }
}
