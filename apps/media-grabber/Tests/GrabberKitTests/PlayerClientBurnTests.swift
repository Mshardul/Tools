@testable import GrabberKit
import TestSupport
import XCTest

final class PlayerClientBurnTests: XCTestCase {
    private typealias Fix = EngineFixture

    private let botCheck = FakeProcessRunner.Script.stderr(
        "ERROR: Sign in to confirm you're not a bot", exitCode: 1
    )
    private let diskFull = FakeProcessRunner.Script.stderr(
        "ERROR: unable to write data: No space left on device", exitCode: 1
    )

    private func successProbe() -> FakeMetadataProbe {
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        return probe
    }

    func testNonYouTubeContextSkipsTheCatalog() async {
        let order = ScriptedPlayerClientOrder(clients: ["ios"])
        let engine = Fix.engine(
            runner: FakeProcessRunner(),
            probe: successProbe(),
            playerClientOrder: order
        )
        let context = await engine.makeContext(url: "https://vimeo.com/1", attempt: 0)
        XCTAssertNil(context.playerClient)
        XCTAssertEqual(order.calls.read { $0 }, 0)
    }

    func testBotCheckBurnsTheClientForThatJobOnly() async {
        let order = ScriptedPlayerClientOrder(clients: ["tv", "ios"])
        let runner = FakeProcessRunner()
        runner.scripts([botCheck, Fix.completingScript(), Fix.completingScript()], forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(
            runner: runner,
            probe: successProbe(),
            cap: 1,
            tuning: EngineTuning.resolved(environment: ["MG_BACKOFF_LADDER": "1"]),
            playerClientOrder: order
        )
        let collector = EventCollector(engine.events)
        let first = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=a"))
        let finished = await collector.waitForState(first) { $0 == .completed }
        XCTAssertTrue(finished)

        let launches = runner.launches.filter { $0.executableURL.lastPathComponent == "yt-dlp" }
        let clients = launches.map { launch in
            launch.arguments.first { $0.contains("player_client=") } ?? "(none)"
        }
        XCTAssertEqual(
            clients.prefix(2).map(\.self),
            ["youtube:player_client=tv", "youtube:player_client=ios"],
            "\(clients)"
        )

        let beforeSecond = runner.launches.count
        let second = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=b"))
        let secondFinished = await collector.waitForState(second) { $0 == .completed }
        XCTAssertTrue(secondFinished)
        let newer = runner.launches.dropFirst(beforeSecond)
        XCTAssertTrue(newer.first?.arguments.contains("youtube:player_client=tv") == true)
    }

    func testRestartAfterBotCheckStartsAtTheFirstClient() async {
        let order = ScriptedPlayerClientOrder(clients: ["tv", "ios"])
        let runner = FakeProcessRunner()
        runner.scripts(
            [botCheck, botCheck, Fix.completingScript()],
            forPathEndingIn: "yt-dlp"
        )
        let engine = Fix.engine(
            runner: runner,
            probe: successProbe(),
            cap: 1,
            tuning: EngineTuning.resolved(environment: ["MG_BACKOFF_LADDER": "1"]),
            maxAutoRetries: 1,
            playerClientOrder: order
        )
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=a"))
        let failed = await collector.waitForState(id) {
            if case .failed = $0 {
                true
            } else {
                false
            }
        }
        XCTAssertTrue(failed)
        await engine.retry(id)
        let finished = await collector.waitForState(id) { $0 == .completed }
        XCTAssertTrue(finished)
        let clients = runner.launches.map { launch in
            launch.arguments.first { $0.contains("player_client=") } ?? "(none)"
        }
        XCTAssertEqual(clients.last, "youtube:player_client=tv", "\(clients)")
    }

    func testDiskFullDoesNotBurnTheClient() async {
        let order = ScriptedPlayerClientOrder(clients: ["tv", "ios"])
        let runner = FakeProcessRunner()
        runner.scripts([diskFull, Fix.completingScript()], forPathEndingIn: "yt-dlp")
        let engine = Fix.engine(
            runner: runner,
            probe: successProbe(),
            cap: 1,
            playerClientOrder: order
        )
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=a"))
        let failed = await collector.waitForState(id) {
            if case .failed = $0 {
                true
            } else {
                false
            }
        }
        XCTAssertTrue(failed)
        await engine.retry(id)
        let finished = await collector.waitForState(id) { $0 == .completed }
        XCTAssertTrue(finished)
        let launches = runner.launches.filter { $0.executableURL.lastPathComponent == "yt-dlp" }
        let clients = launches.map { launch in
            launch.arguments.first { $0.contains("player_client=") } ?? "(none)"
        }
        XCTAssertEqual(
            clients.prefix(2).map(\.self),
            ["youtube:player_client=tv", "youtube:player_client=tv"],
            "\(clients)"
        )
    }

    func testBurnedClientsAreNotPersisted() {
        let job = DownloadJob(request: Fix.request())
        job.burnedPlayerClients = ["tv"]
        let data = try? JSONEncoder().encode(DownloadEngine.persistedJob(from: job))
        let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("burnedPlayerClients"))
    }

    func testPotStaysTiedToARunningYouTubeHelper() async {
        let running = FakePotProvider(
            status: .running(port: 4416),
            baseURL: URL(string: "http://127.0.0.1:4416")
        )
        let missing = FakePotProvider(status: .missing)
        let up = Fix.engine(
            runner: FakeProcessRunner(),
            probe: successProbe(),
            potProvider: running
        )
        let down = Fix.engine(
            runner: FakeProcessRunner(),
            probe: successProbe(),
            potProvider: missing
        )
        let withPot = await up.makeContext(url: "https://youtube.com/watch?v=a", attempt: 0)
        let without = await down.makeContext(url: "https://youtube.com/watch?v=a", attempt: 0)
        XCTAssertEqual(withPot.potBaseURL, URL(string: "http://127.0.0.1:4416"))
        XCTAssertNil(without.potBaseURL)
    }
}

final class ScriptedPlayerClientOrder: PlayerClientOrdering, @unchecked Sendable {
    let clients: [String]
    let calls = LockedBox(0)

    init(clients: [String]) {
        self.clients = clients
    }

    func order() async -> [String] {
        calls.mutate { $0 += 1 }
        return clients
    }
}
