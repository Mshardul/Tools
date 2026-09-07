@testable import GrabberKit
import TestSupport
import XCTest

final class EnginePreviewTests: XCTestCase {
    private typealias Fix = EngineFixture

    private func successProbe() -> FakeMetadataProbe {
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        return probe
    }

    private func joinedArgs(_ launch: ProcessLaunch) -> String {
        launch.arguments.joined(separator: " ")
    }

    func testPreviewSuccessCreatesNoJob() async {
        let engine = Fix.engine(runner: FakeProcessRunner(), probe: successProbe())
        let result = await engine.preview("https://youtube.com/watch?v=x")
        guard case .success = result else {
            XCTFail("expected success")
            return
        }
        let snapshot = await engine.currentSnapshot()
        XCTAssertTrue(snapshot.jobs.isEmpty)
    }

    func testPreviewNetworkDown() async {
        let net = FakeNetworkMonitor(startOnline: true)
        let engine = Fix.engine(
            runner: FakeProcessRunner(),
            probe: successProbe(),
            networkMonitor: net
        )
        let collector = EventCollector(engine.events)
        net.goOffline()
        let halted = await waitForHalt(collector, .networkDown)
        XCTAssertTrue(halted)

        let result = await engine.preview("https://youtube.com/watch?v=x")
        XCTAssertEqual(result, .failure(.network))
    }

    func testPreviewHostBlockedDuringCooldown() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1000))
        let runner = FakeProcessRunner()
        runner.script(
            .stderr("ERROR: HTTP Error 429: Too Many Requests", exitCode: 1),
            forPathEndingIn: "yt-dlp"
        )
        let engine = Fix.engine(
            runner: runner, probe: successProbe(), cap: 1, clock: clock
        )
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=a"))
        let cooled = await collector.waitForState(id) {
            if case .cooldown = $0 {
                return true
            }
            return false
        }
        XCTAssertTrue(cooled)

        let result = await engine.preview("https://youtube.com/watch?v=b")
        XCTAssertEqual(result, .failure(.hostBlocked))
    }

    func testPreviewYouTubeProbeArgvIncludesTvClient() async throws {
        let runner = FakeProcessRunner()
        runner.script(
            .stdout(Fixture.text("ytdlp-J-youtube-formats.json")),
            forPathEndingIn: "yt-dlp"
        )
        let probe = MetadataProbe(ytDlpURL: Fix.ytDlp, runner: runner)
        let engine = Fix.engine(runner: runner, probe: probe)
        let result = await engine.preview("https://youtube.com/watch?v=x")
        guard case .success = result else {
            XCTFail("expected success")
            return
        }
        let launch = try XCTUnwrap(runner.launches.last)
        XCTAssertTrue(joinedArgs(launch).contains("player_client=tv"))
    }

    func testPreviewArchiveOrgOmitsPlayerClient() async throws {
        let runner = FakeProcessRunner()
        runner.script(
            .stdout(Fixture.text("ytdlp-J-youtube-formats.json")),
            forPathEndingIn: "yt-dlp"
        )
        let probe = MetadataProbe(ytDlpURL: Fix.ytDlp, runner: runner)
        let engine = Fix.engine(runner: runner, probe: probe)
        let result = await engine.preview("https://archive.org/details/x")
        guard case .success = result else {
            XCTFail("expected success")
            return
        }
        let launch = try XCTUnwrap(runner.launches.last)
        XCTAssertFalse(joinedArgs(launch).contains("player_client="))
    }

    private func waitForHalt(_ collector: EventCollector, _ reason: QueueHaltReason) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if collector.latestSnapshot()?.queueHalt == reason {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}
