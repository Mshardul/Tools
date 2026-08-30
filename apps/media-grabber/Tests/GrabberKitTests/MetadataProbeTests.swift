@testable import GrabberKit
import TestSupport
import XCTest

final class MetadataProbeTests: XCTestCase {
    private let ytDlp = URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp")

    private func fixture(_ name: String, _ ext: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func probe(_ runner: FakeProcessRunner) -> MetadataProbe {
        MetadataProbe(ytDlpURL: ytDlp, runner: runner)
    }

    func test_validVideo_returnsTitleAndDuration() async throws {
        let json = try fixture("ytdlp-J-video", "json")
        let runner = FakeProcessRunner()
        runner.script(.stdout(json), forPathEndingIn: "yt-dlp")
        let result = await probe(runner).probe("https://archive.org/details/BigBuckBunny_124")

        guard case let .success(meta) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(meta.title, "Big Buck Bunny")
        XCTAssertEqual(meta.durationSeconds, 596)
        XCTAssertFalse(meta.isPlaylist)
        XCTAssertEqual(meta.sourceURL, "https://archive.org/details/BigBuckBunny_124")
    }

    func test_noDurationField_returnsNilDuration() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout(#"{"title":"Clip","_type":"video"}"#), forPathEndingIn: "yt-dlp")
        let result = await probe(runner).probe("https://x/y")
        guard case let .success(meta) = result else {
            return XCTFail("expected success")
        }
        XCTAssertNil(meta.durationSeconds)
    }

    func test_badURL_mapsToBadURL() async {
        let runner = FakeProcessRunner()
        runner.script(
            .stderr("ERROR: [generic] 'x' is not a valid URL", exitCode: 1),
            forPathEndingIn: "yt-dlp"
        )
        let result = await probe(runner).probe("x")
        XCTAssertEqual(result, .failure(.badURL))
    }

    func test_unsupported_mapsToUnsupported() async {
        let runner = FakeProcessRunner()
        runner.script(
            .stderr("ERROR: Unsupported URL: https://x/y", exitCode: 1),
            forPathEndingIn: "yt-dlp"
        )
        let result = await probe(runner).probe("https://x/y")
        XCTAssertEqual(result, .failure(.unsupported))
    }

    func test_unavailable_mapsToUnavailable() async throws {
        let stderr = try fixture("ytdlp-J-unavailable", "txt")
        let runner = FakeProcessRunner()
        runner.script(.stderr(stderr, exitCode: 1), forPathEndingIn: "yt-dlp")
        let result = await probe(runner).probe("https://youtube.com/watch?v=x")
        XCTAssertEqual(result, .failure(.unavailable))
    }

    func test_networkFailure_mapsToNetwork() async {
        let runner = FakeProcessRunner()
        runner.script(
            .stderr(
                "ERROR: Unable to download webpage: Failed to resolve 'x' "
                    + "(nodename nor servname provided, or not known)",
                exitCode: 1
            ),
            forPathEndingIn: "yt-dlp"
        )
        let result = await probe(runner).probe("https://x/y")
        XCTAssertEqual(result, .failure(.network))
    }

    func test_exitZeroGarbageJSON_mapsToMalformed() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout("not json at all"), forPathEndingIn: "yt-dlp")
        let result = await probe(runner).probe("https://x/y")
        XCTAssertEqual(result, .failure(.malformedOutput))
    }

    func test_exitZeroNoTitle_mapsToMalformed() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout(#"{"_type":"video","id":"x"}"#), forPathEndingIn: "yt-dlp")
        let result = await probe(runner).probe("https://x/y")
        XCTAssertEqual(result, .failure(.malformedOutput))
    }

    func test_ytDlpMissing_mapsToYtDlpMissing() async {
        let runner = FakeProcessRunner()
        // No script for yt-dlp → fake returns exit 127.
        let result = await probe(runner).probe("https://x/y")
        XCTAssertEqual(result, .failure(.ytDlpMissing))
    }

    func test_serialization_secondCallWaits() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .milliseconds(60)
        runner.script(.stdout(#"{"title":"A"}"#), forPathEndingIn: "yt-dlp")
        let sut = probe(runner)

        async let first = sut.probe("https://x/1")
        async let second = sut.probe("https://x/2")
        _ = await (first, second)

        XCTAssertEqual(runner.maxConcurrent, 1, "probes must not overlap")
    }
}
