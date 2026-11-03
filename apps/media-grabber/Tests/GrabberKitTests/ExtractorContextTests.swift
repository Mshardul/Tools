@testable import GrabberKit
import TestSupport
import XCTest

final class ExtractorContextTests: XCTestCase {
    func testEngineContextLoadsBundledZoomPluginWithoutShield() async {
        let engine = EngineFixture.engine(
            runner: FakeProcessRunner(),
            probe: FakeMetadataProbe(default: .failure(.network))
        )
        let context = await engine.makeContext(
            url: "https://example.zoom.us/rec/share/x",
            attempt: 0
        )
        let pluginFile = "zoomfix/yt_dlp_plugins/extractor/zoom_share_passcode.py"
        let found = context.pluginDirs.contains {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent(pluginFile).path)
        }
        XCTAssertTrue(found, "plugin dirs: \(context.pluginDirs)")
    }

    func testDownloadLaunchKeepsPluginBytecodeOutOfTheAppBundle() async {
        let runner = FakeProcessRunner()
        runner.script(FakeProcessRunner.Script(lines: [], exitCode: 0), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = EngineFixture.engine(runner: runner, probe: probe)
        _ = await submitJob(engine, EngineFixture.request(url: "https://example.zoom.us/rec/share/x"))
        for _ in 0 ..< 100 where runner.launches.isEmpty {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(runner.launches.first?.environment?["PYTHONDONTWRITEBYTECODE"], "1")
    }

    func testNoneHasNilFlags() {
        XCTAssertEqual(ExtractorContext.none.pluginDirs, [])
        XCTAssertNil(ExtractorContext.none.potBaseURL)
        XCTAssertNil(ExtractorContext.none.playerClient)
        XCTAssertNil(ExtractorContext.none.cookieArgument)
    }
}
