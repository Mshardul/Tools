import Foundation
@testable import GrabberKit
@testable import MediaGrabber
import TestSupport
import XCTest

@MainActor
final class AppModelTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard
    private var logDirectory: URL!

    override func setUp() async throws {
        suiteName = "mg.appmodel.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        logDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-appmodel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: logDirectory)
    }

    private func makeModel(
        engine: FakeEngine = FakeEngine(),
        probe: FakeMetadataProbe = FakeMetadataProbe(.failure(.malformedOutput)),
        envReady: Bool = true,
        debugFlags: DebugFlags = DebugFlags(),
        revealSink: FakeRevealSink = FakeRevealSink(),
        openURLSink: FakeOpenURLSink = FakeOpenURLSink(),
        engineJobLogDir: URL? = nil,
        persistence: FakeQueuePersisting? = nil
    ) -> AppModel {
        AppModelTestHelpers.makeModel(
            defaults: defaults,
            logDirectory: logDirectory,
            engine: engine,
            probe: probe,
            envReady: envReady,
            debugFlags: debugFlags,
            revealSink: revealSink,
            openURLSink: openURLSink,
            engineJobLogDir: engineJobLogDir,
            persistence: persistence
        )
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
        let model = makeModel(envReady: true, debugFlags: DebugFlags(forceOnboarding: true))
        await model.onAppear()
        XCTAssertTrue(model.needsOnboarding)
    }

    func test_resolvePasted_success_setsResolved() async {
        let model =
            makeModel(probe: FakeMetadataProbe(.success(AppModelTestHelpers
                    .meta(title: "Big Buck Bunny"))))
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
        prefs.lastUsedDownloadFolder = dest

        let model = AppModel(
            engine: engine,
            probe: FakeMetadataProbe(.success(AppModelTestHelpers.meta(url: "https://src/v"))),
            installer: OnboardingInstaller(
                probe: FakeEnvironmentProbe(ready: true),
                runner: NullRunner()
            ),
            prefs: prefs,
            log: LogWriter(directory: logDirectory),
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

    func test_grab_writesLastSelectedFromOverrides() async {
        let model = makeModel(
            probe: FakeMetadataProbe(.success(AppModelTestHelpers.meta()))
        )
        await model.resolvePasted("https://x/y")
        await model.grab(overrides: RunwayOverrides(
            kind: .video(maxHeight: 720),
            destFolder: nil
        ))
        XCTAssertEqual(model.prefs.lastMediaType, .video)
        XCTAssertEqual(model.prefs.lastVideoHeight, 720)
    }

    func test_grab_keepsJobReference() async {
        let engine = FakeEngine()
        let jobID = UUID()
        engine.stubNextResult(.queued(jobID))
        let model = makeModel(
            engine: engine,
            probe: FakeMetadataProbe(.success(AppModelTestHelpers.meta()))
        )
        await model.resolvePasted("https://x/y")
        await model.grab()
        XCTAssertEqual(model.lastSubmittedJobID, jobID)
    }

    func test_cancelJob_callsEngineCancel() async {
        let engine = FakeEngine()
        let jobID = UUID()
        engine.stubNextResult(.queued(jobID))
        let model = makeModel(
            engine: engine,
            probe: FakeMetadataProbe(.success(AppModelTestHelpers.meta()))
        )
        await model.resolvePasted("https://x/y")
        await model.grab()
        await model.cancelJob()
        XCTAssertEqual(engine.cancelledIDs, [jobID])
    }

    func test_grab_duplicateExists_promptsConfirm_confirmResubmitsForce() async {
        let engine = FakeEngine()
        let existingID = UUID()
        let newID = UUID()
        engine.stubSubmitResults(
            .duplicateExists(existing: existingID, wasCompleted: false),
            .queued(newID)
        )
        let model = makeModel(
            engine: engine,
            probe: FakeMetadataProbe(.success(AppModelTestHelpers.meta()))
        )
        await model.resolvePasted("https://x/y")

        let grabTask = Task { await model.grab() }
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertNotNil(model.pendingConfirmation)
        model.resolveConfirmation(true, suppressFutures: false)
        await grabTask.value

        XCTAssertEqual(engine.submittedForces, [false, true])
        XCTAssertEqual(model.lastSubmittedJobID, newID)
        XCTAssertEqual(model.scrollToRowID, newID)
    }

    func test_grab_duplicateCompleted_cancel_scrollsToExistingRow() async {
        let engine = FakeEngine()
        let existingID = UUID()
        engine.stubNextResult(.duplicateExists(existing: existingID, wasCompleted: true))
        let model = makeModel(
            engine: engine,
            probe: FakeMetadataProbe(.success(AppModelTestHelpers.meta()))
        )
        await model.resolvePasted("https://x/y")

        let grabTask = Task { await model.grab() }
        try? await Task.sleep(for: .milliseconds(20))
        model.resolveConfirmation(false, suppressFutures: false)
        await grabTask.value

        XCTAssertEqual(engine.submittedForces, [false])
        XCTAssertEqual(model.scrollToRowID, existingID)
    }

    func test_reveal_allFilesMissing_presentsNotice_logsRevealTargetMissing() async throws {
        let engine = FakeEngine()
        let revealSink = FakeRevealSink()
        let model = makeModel(engine: engine, revealSink: revealSink)
        await model.onAppear()

        let jobID = UUID()
        let missingFile = URL(fileURLWithPath: "/tmp/missing-\(UUID().uuidString).mp4")
        engine.emit(.snapshot(QueueSnapshot(
            jobs: [AppModelTestHelpers.jobSnapshot(id: jobID, outputFiles: [missingFile])],
            revision: 1,
            queueHalt: nil,
            generatedAt: .init()
        )))
        try await Task.sleep(for: .milliseconds(50))

        let revealTask = Task { await model.reveal(jobID: jobID) }
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertNotNil(model.pendingConfirmation)
        XCTAssertNil(model.pendingConfirmation?.cancelTitle)
        model.resolveConfirmation(true, suppressFutures: false)
        await revealTask.value

        XCTAssertTrue(revealSink.revealed.isEmpty)
        XCTAssertTrue(try AppModelTestHelpers.logContainsEvent(
            "reveal.target_missing",
            in: logDirectory
        ))
    }

    func test_onboardingFinished_callsEngineRevalidate() async {
        let engine = FakeEngine()
        let model = makeModel(engine: engine)
        await model.onboardingFinished()
        XCTAssertTrue(engine.revalidateCalled)
    }

    func test_restoreProducedJobs_forcesHasGrabbedOnce() async {
        let engine = FakeEngine()
        let persistence = FakeQueuePersisting()
        let job = AppModelTestHelpers.jobSnapshot()
        engine.setRestoreSnapshot(QueueSnapshot(
            jobs: [job],
            revision: 1,
            queueHalt: nil,
            generatedAt: .init()
        ))
        let model = makeModel(engine: engine, persistence: persistence)

        await model.performLaunchSetup()

        XCTAssertTrue(engine.restoreCalled)
        XCTAssertEqual(model.rowStore.rows.count, 1)
    }

    func test_resetAllSettings_restoresDefaults() {
        let model = makeModel()
        model.prefs.defaultVideoHeight = 480
        model.prefs.theme = .tapeDeck
        model.resetAllSettings()
        XCTAssertEqual(model.prefs.defaultVideoHeight, 1080)
        XCTAssertEqual(model.prefs.theme, .aurora)
    }

    func test_debugResetState_skipsPersistenceLoads() async {
        let engine = FakeEngine()
        let persistence = FakeQueuePersisting()
        engine.setRestoreSnapshot(QueueSnapshot(
            jobs: [AppModelTestHelpers.jobSnapshot()],
            revision: 1,
            queueHalt: nil,
            generatedAt: .init()
        ))
        let model = makeModel(
            engine: engine,
            debugFlags: DebugFlags(resetState: true),
            persistence: persistence
        )

        await model.performLaunchSetup()

        XCTAssertFalse(engine.restoreCalled)
        XCTAssertTrue(model.rowStore.rows.isEmpty)
    }
}
