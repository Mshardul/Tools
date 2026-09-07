@testable import GrabberKit
import TestSupport
import XCTest

final class MetadataProbeFormatTests: XCTestCase {
    private let ytDlp = URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp")

    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testYouTubeFormatsListsHeightsAndTracks() throws {
        let json = try fixture("ytdlp-J-youtube-formats")
        let result = MetadataProbe.decodeForTest(json, sourceURL: "https://youtube.com/watch?v=abc")
        guard case let .success(meta) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(meta.formatAvailability, .listed)
        XCTAssertEqual(meta.videoHeights, [1080, 720])
        XCTAssertEqual(meta.audioTracks.count, 2)
        let ja = meta.audioTracks.first { $0.languageCode == "ja" }
        let en = meta.audioTracks.first { $0.languageCode == "en" }
        XCTAssertEqual(ja?.id, "ja|orig")
        XCTAssertEqual(ja?.isOriginal, true)
        XCTAssertEqual(ja?.isDefault, false)
        XCTAssertEqual(ja?.label, "Japanese (original)")
        XCTAssertEqual(en?.id, "en|dub")
        XCTAssertEqual(en?.isOriginal, false)
        XCTAssertEqual(en?.isDefault, true)
        XCTAssertEqual(en?.label, "English")
    }

    func testAudioOnlyListedWithEmptyHeights() throws {
        let json = try fixture("ytdlp-J-audio-only")
        let result = MetadataProbe.decodeForTest(json, sourceURL: "https://youtube.com/watch?v=a")
        guard case let .success(meta) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(meta.formatAvailability, .listed)
        XCTAssertEqual(meta.videoHeights, [])
        XCTAssertEqual(meta.audioTracks.count, 1)
        XCTAssertEqual(meta.audioTracks.first?.languageCode, "en")
    }

    func testNoLanguagesYieldsSyntheticDefault() throws {
        let json = try fixture("ytdlp-J-no-languages")
        let result = MetadataProbe.decodeForTest(json, sourceURL: "https://archive.org/x")
        guard case let .success(meta) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(meta.formatAvailability, .listed)
        XCTAssertEqual(meta.videoHeights, [720])
        XCTAssertEqual(meta.audioTracks, [
            AudioTrack(
                id: "default",
                languageCode: nil,
                label: "Default",
                isOriginal: false,
                isDefault: true
            )
        ])
    }

    func testMissingFormatsKeyIsUnknown() throws {
        let json = try fixture("ytdlp-J-no-formats")
        let result = MetadataProbe.decodeForTest(json, sourceURL: "https://x/y")
        guard case let .success(meta) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(meta.formatAvailability, .unknown)
        XCTAssertEqual(meta.videoHeights, [])
        XCTAssertEqual(meta.audioTracks, [])
    }

    func testProbeArgvIncludesPlayerClient() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout(#"{"title":"Clip"}"#), forPathEndingIn: "yt-dlp")
        let ctx = ExtractorContext(
            pluginDirs: [],
            potBaseURL: nil,
            playerClient: "tv",
            cookieArgument: nil
        )
        let sut = MetadataProbe(ytDlpURL: ytDlp, runner: runner)
        _ = await sut.probe("https://youtube.com/watch?v=x", context: ctx)
        let launch = runner.launches.first
        XCTAssertNotNil(launch)
        XCTAssertTrue(launch?.arguments.contains("youtube:player_client=tv") == true)
    }
}
