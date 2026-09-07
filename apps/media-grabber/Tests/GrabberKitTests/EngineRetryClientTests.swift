@testable import GrabberKit
import TestSupport
import XCTest

final class EngineRetryClientTests: XCTestCase {
    private typealias Fix = EngineFixture

    private func successProbe() -> FakeMetadataProbe {
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip", durationSeconds: 10))
        return probe
    }

    private func youtubeRequest(destFolder: URL) -> DownloadRequest {
        Fix.request(url: "https://youtube.com/watch?v=x", destFolder: destFolder)
    }

    private func meta(_ request: DownloadRequest) -> MediaMetadata {
        MediaMetadata(
            title: "Clip",
            durationSeconds: 10,
            isPlaylist: false,
            sourceURL: request.url,
            extractor: "youtube"
        )
    }

    private func joinedArgs(_ launch: ProcessLaunch) -> String {
        launch.arguments.joined(separator: " ")
    }

    func testBotCheckRetryUsesIosClient() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let dir = Fix.scratchDestFolder()
        let file = dir.appendingPathComponent("Clip.mp4")
        FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
        let runner = FakeProcessRunner()
        runner.scripts(
            [
                .stderr("ERROR: Sign in to confirm you're not a bot", exitCode: 1),
                Fix.completingScript([.stdout("[download] Destination: \(file.path)")])
            ],
            forPathEndingIn: "yt-dlp"
        )
        let engine = Fix.engine(
            runner: runner,
            probe: successProbe(),
            cap: 1,
            clock: clock,
            maxAutoRetries: 2
        )
        let collector = EventCollector(engine.events)
        let request = youtubeRequest(destFolder: dir)
        let result = await engine.submit(request, force: false, prefetchedMetadata: meta(request))
        guard case let .queued(id) = result else {
            return XCTFail("expected queued")
        }
        _ = await collector.waitForState(id) { state in
            guard state == .queued else {
                return false
            }
            let attempt = collector.latestSnapshot()?.jobs.first { $0.id == id }?.attempt ?? 0
            return attempt >= 1
        }
        clock.advance(by: .seconds(600))
        try? await Task.sleep(for: .milliseconds(80))
        await expectState(collector, id) { $0 == .completed }

        XCTAssertGreaterThanOrEqual(runner.launches.count, 2)
        XCTAssertTrue(joinedArgs(runner.launches[0]).contains("player_client=tv"))
        XCTAssertTrue(joinedArgs(runner.launches[1]).contains("player_client=ios"))
    }

    func testSabrGatedDoesNotAutoRetry() async {
        let runner = FakeProcessRunner()
        runner.script(
            .stderr("ERROR: only images are available for this video (sabr)", exitCode: 1),
            forPathEndingIn: "yt-dlp"
        )
        let engine = Fix.engine(
            runner: runner, probe: successProbe(), cap: 1, maxAutoRetries: 2
        )
        let collector = EventCollector(engine.events)
        let request = youtubeRequest(destFolder: Fix.scratchDestFolder())
        let result = await engine.submit(request, force: false, prefetchedMetadata: meta(request))
        guard case let .queued(id) = result else {
            return XCTFail("expected queued")
        }
        await expectState(collector, id) { state in
            if case .failed(.sabrGated) = state {
                return true
            }
            return false
        }
        XCTAssertEqual(runner.launches.count, 1)
    }
}
