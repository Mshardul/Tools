@testable import GrabberKit
import TestSupport
import XCTest

final class MetadataProbePlaylistTests: XCTestCase {
    private let ytDlp = URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp")

    func testProbePlaylistLaunchUsesFlatPlaylistArguments() async throws {
        let runner = FakeProcessRunner()
        runner.script(.stdout(Fixture.text("ytdlp-J-flat-playlist.json")), forPathEndingIn: "yt-dlp")
        let sut = MetadataProbe(ytDlpURL: ytDlp, runner: runner)

        _ = await sut.probePlaylist("https://example.com/playlist", context: .none)

        let launch = try XCTUnwrap(runner.launches.first)
        XCTAssertTrue(launch.arguments.contains("-J"))
        XCTAssertTrue(launch.arguments.contains("--flat-playlist"))
        XCTAssertTrue(launch.arguments.contains("--no-warnings"))
        XCTAssertTrue(launch.arguments.contains("--no-update"))
        XCTAssertTrue(launch.arguments.contains("https://example.com/playlist"))
        XCTAssertFalse(launch.arguments.contains("--no-playlist"))
    }

    func testProbePlaylistDecodesFixtureDump() async throws {
        let runner = FakeProcessRunner()
        runner.script(.stdout(Fixture.text("ytdlp-J-flat-playlist.json")), forPathEndingIn: "yt-dlp")
        let sut = MetadataProbe(ytDlpURL: ytDlp, runner: runner)

        let result = await sut.probePlaylist("https://example.com/playlist", context: .none)

        let dump = try result.get()
        XCTAssertEqual(dump.title, "Focus — deep work")
        XCTAssertEqual(dump.entries.count, 2)
    }

    func testCancellingInFlightProbeCancelsRunner() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(5)
        runner.script(.stdout(#"{"title":"Delayed"}"#), forPathEndingIn: "yt-dlp")
        let sut = MetadataProbe(ytDlpURL: ytDlp, runner: runner)

        let task = Task { await sut.probe("https://example.com/delayed") }
        await Task.yield()
        task.cancel()
        _ = await task.value

        let cancelledCount = runner.cancelledCount
        XCTAssertGreaterThanOrEqual(cancelledCount, 1)
    }

    func testCancellingTailProbeDoesNotBlockNextProbe() async throws {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(5)
        runner.scripts([
            .stdout(#"{"title":"A"}"#),
            .stdout(#"{"title":"B"}"#)
        ], forPathEndingIn: "yt-dlp")
        let sut = MetadataProbe(ytDlpURL: ytDlp, runner: runner)

        let first = Task { await sut.probe("https://example.com/a") }
        await Task.yield()
        let second = Task { await sut.probe("https://example.com/b") }
        first.cancel()
        _ = await first.value
        let result = await second.value

        let metadata = try result.get()
        XCTAssertEqual(metadata.title, "B")
    }
}
