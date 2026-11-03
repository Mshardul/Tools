import Foundation
@testable import GrabberKit
@testable import MediaGrabber
import TestSupport
import XCTest

private final class PasscodeGatedProbe: MetadataProbing, @unchecked Sendable {
    private let calls = LockedBox(0)
    private let slowWithoutPasscode: Duration

    init(slowWithoutPasscode: Duration = .zero) {
        self.slowWithoutPasscode = slowWithoutPasscode
    }

    var callCount: Int {
        calls.read { $0 }
    }

    func probe(
        _ url: String,
        context: ExtractorContext,
        onWait _: (@Sendable (Date?) -> Void)?
    ) async -> Result<MediaMetadata, MetadataError> {
        calls.mutate { $0 += 1 }
        guard context.videoPassword != nil else {
            try? await Task.sleep(for: slowWithoutPasscode)
            return .failure(.passcodeRequired)
        }
        return .success(MediaMetadata(
            title: "Clip", durationSeconds: 10, isPlaylist: false, sourceURL: url, extractor: "zoom"
        ))
    }

    func probePlaylist(_: String, context _: ExtractorContext) async -> Result<PlaylistDump, MetadataError> {
        .failure(.malformedOutput)
    }
}

@MainActor
final class PasscodeFlowIntegrationTests: XCTestCase {
    private var logDir: URL!
    private let url = "https://example.zoom.us/rec/share/abc"

    override func setUp() {
        super.setUp()
        logDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-pcflow-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: logDir)
        super.tearDown()
    }

    private func makeModel(
        runner: FakeProcessRunner,
        probe: PasscodeGatedProbe = PasscodeGatedProbe()
    ) throws -> AppModel {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        defaults.set(true, forKey: "mg.hasCompletedOnboarding")
        let prefs = Preferences(defaults: defaults)
        let engine = DownloadEngine(
            dependencies: EngineDependencies(
                runner: runner,
                probe: probe,
                envProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
                ytDlpURL: URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"),
                jobLogDir: logDir,
                debugFlags: EngineDebugFlags(concurrencyCapOverride: 1)
            ),
            preferences: prefs
        )
        return AppModel(
            engine: engine,
            installer: OnboardingInstaller(probe: FakeEnvironmentProbe(ready: true), runner: NullRunner()),
            prefs: prefs,
            log: LogWriter(directory: logDir),
            envProbe: FakeEnvironmentProbe(ready: true),
            ytDlpUpdater: FakeYtDlpUpdater(),
            debugFlags: DebugFlags(),
            defaults: defaults,
            notificationRouter: FakeNotificationRouter(),
            revealSink: FakeRevealSink(),
            openURLSink: FakeOpenURLSink(),
            appUpdateChecker: AppUpdateChecker(),
            appVersion: "0.0.0",
            engineJobLogDir: logDir,
            persistence: nil
        )
    }

    func test_theSameLinkPastedTwiceWhileCheckingIsProbedOnce() async throws {
        let probe = PasscodeGatedProbe(slowWithoutPasscode: .milliseconds(200))
        let model = try makeModel(runner: FakeProcessRunner(), probe: probe)
        let first = Task { await model.resolvePasted(url) }
        let second = Task { await model.resolvePasted(url) }
        await first.value
        await second.value
        XCTAssertEqual(probe.callCount, 1)
        XCTAssertTrue(model.isPasscodeSheetShown)
    }

    func test_aStaleFailureAfterThePasscodeWasSubmittedDoesNotReopenThePrompt() async throws {
        let probe = PasscodeGatedProbe(slowWithoutPasscode: .milliseconds(300))
        let model = try makeModel(runner: FakeProcessRunner(), probe: probe)
        let stale = Task { await model.resolvePasted(url) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        model.passcodeNeeded = PasscodePrompt(target: .link(url), url: url, wasRejected: false)
        await model.submitPasscode("p")
        await stale.value
        XCTAssertNil(model.passcodeNeeded)
        XCTAssertFalse(model.isPasscodeSheetShown)
        XCTAssertNotNil(model.resolved)
        XCTAssertNil(model.probeError)
    }

    func test_pastePasscodeGrab_launchesYtDlpWithThePasscode() async throws {
        let runner = FakeProcessRunner()
        runner.script(FakeProcessRunner.Script(lines: [], exitCode: 0), forPathEndingIn: "yt-dlp")
        let model = try makeModel(runner: runner)

        await model.resolvePasted(url)
        XCTAssertTrue(model.isPasscodeSheetShown)
        await model.submitPasscode("secret")
        XCTAssertNotNil(model.resolved)
        await model.grab()

        for _ in 0 ..< 200 where runner.launches.isEmpty {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let flags = (runner.launches.first?.arguments ?? []).filter { $0.hasPrefix("--video-password") }
        XCTAssertEqual(flags, ["--video-password=secret"])
    }
}
