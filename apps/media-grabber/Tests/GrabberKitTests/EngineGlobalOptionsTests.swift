@testable import GrabberKit
import TestSupport
import XCTest

final class EngineGlobalOptionsTests: XCTestCase {
    private typealias Fix = EngineFixture

    func test_spawnedArgvCarriesForceIPv4Flag() async throws {
        let runner = FakeProcessRunner()
        runner.script(Fix.completingScript(), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))

        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let prefs = Preferences(defaults: defaults)
        prefs.forceIPv4 = true

        let engine = Fix.engine(runner: runner, probe: probe, preferences: prefs)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        await expectState(collector, id) { $0 == .completed }

        let download = try XCTUnwrap(
            runner.launches.first { $0.executableURL.lastPathComponent == "yt-dlp" }
        )
        XCTAssertTrue(download.arguments.contains("-4"))
    }
}
