import Foundation
@testable import GrabberKit
@testable import MediaGrabber
import XCTest

@MainActor
final class AppModelTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUp() async throws {
        suiteName = "mg.appmodel.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeModel(
        engine: FakeEngine = FakeEngine(),
        probe: FakeMetadataProbe = FakeMetadataProbe(.failure(.malformedOutput)),
        envReady: Bool = true,
        forceOnboarding: Bool = false,
        revealSink: FakeRevealSink = FakeRevealSink()
    ) -> AppModel {
        AppModel(
            engine: engine,
            probe: probe,
            installer: OnboardingInstaller(
                probe: FakeEnvironmentProbe(ready: envReady),
                runner: NullRunner()
            ),
            prefs: Preferences(defaults: defaults),
            log: LogWriter(
                directory: URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("mg-appmodel-\(UUID().uuidString)")
            ),
            envProbe: FakeEnvironmentProbe(ready: envReady),
            forceOnboarding: forceOnboarding,
            revealSink: revealSink
        )
    }

    private func meta(title: String = "Clip", url: String = "https://x/y") -> MediaMetadata {
        MediaMetadata(title: title, durationSeconds: 10, isPlaylist: false, sourceURL: url)
    }

    func test_onAppear_depsPresent_noOnboarding() async {
        let model = makeModel(envReady: true)
        await model.onAppear()
        XCTAssertFalse(model.needsOnboarding)
    }

    func test_onAppear_depsMissing_needsOnboarding() async {
        let model = makeModel(envReady: false)
        await model.onAppear()
        XCTAssertTrue(model.needsOnboarding)
    }

    func test_forceOnboardingFlag_overrides() async {
        let model = makeModel(envReady: true, forceOnboarding: true)
        await model.onAppear()
        XCTAssertTrue(model.needsOnboarding)
    }

    func test_resolvePasted_success_setsResolved() async {
        let model = makeModel(probe: FakeMetadataProbe(.success(meta(title: "Big Buck Bunny"))))
        await model.resolvePasted("https://x/y")
        XCTAssertEqual(model.resolved?.title, "Big Buck Bunny")
        XCTAssertNil(model.probeError)
    }

    func test_resolvePasted_badURL_setsError() async {
        let model = makeModel(probe: FakeMetadataProbe(.failure(.badURL)))
        await model.resolvePasted("not a url")
        XCTAssertNotNil(model.probeError)
        XCTAssertNil(model.resolved)
    }

    func test_grab_buildsRequestFromPrefsAndResolved() async {
        let engine = FakeEngine()
        let dest = URL(fileURLWithPath: "/tmp/x")
        let prefs = Preferences(defaults: defaults)
        prefs.lastUsedDestFolder = dest

        let model = AppModel(
            engine: engine,
            probe: FakeMetadataProbe(.success(meta(url: "https://src/v"))),
            installer: OnboardingInstaller(
                probe: FakeEnvironmentProbe(ready: true),
                runner: NullRunner()
            ),
            prefs: prefs,
            log: LogWriter(
                directory: URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("mg-grab-\(UUID().uuidString)")
            ),
            envProbe: FakeEnvironmentProbe(ready: true)
        )
        await model.resolvePasted("https://src/v")
        await model.grab()

        let request = try? XCTUnwrap(engine.submittedRequests.first)
        XCTAssertEqual(request?.url, "https://src/v")
        XCTAssertEqual(request?.kind, .video(maxHeight: 1080))
        XCTAssertEqual(request?.destFolder, dest)
        XCTAssertEqual(request?.container, "mp4")
    }

    func test_grab_keepsJobReference() async {
        let engine = FakeEngine()
        let jobID = UUID()
        engine.stubNextResult(.queued(jobID))
        let model = makeModel(engine: engine, probe: FakeMetadataProbe(.success(meta())))
        await model.resolvePasted("https://x/y")
        await model.grab()
        XCTAssertEqual(model.lastSubmittedJobID, jobID)
    }

    func test_reveal_callsWorkspaceWithOutputFiles() throws {
        throw XCTSkip("reveal() output-file wiring depends on RowStore, not yet built")
    }

    func test_cancelJob_callsEngineCancel() async {
        let engine = FakeEngine()
        let jobID = UUID()
        engine.stubNextResult(.queued(jobID))
        let model = makeModel(engine: engine, probe: FakeMetadataProbe(.success(meta())))
        await model.resolvePasted("https://x/y")
        await model.grab()
        await model.cancelJob()
        XCTAssertEqual(engine.cancelledIDs, [jobID])
    }
}

private struct NullRunner: ProcessRunning {
    func run(_: ProcessLaunch) -> ProcessExecution {
        let (stream, continuation) = AsyncStream<ProcessLine>.makeStream()
        continuation.finish()
        return ProcessExecution(lines: stream) { ProcessResult(exitCode: 0, wasCancelled: false) }
    }
}
