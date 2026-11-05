@testable import GrabberKit
import TestSupport
import XCTest

@MainActor
final class OnboardingInstallerTests: XCTestCase {
    func test_toolsPresent_runsTheCanaryAndProceeds() async {
        let probe = FakeMetadataProbe(default: FakeMetadataProbe.success(title: "Big Buck Bunny"))
        let installer = OnboardingInstaller(
            probe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
            runner: FakeProcessRunner(),
            metadataProbe: probe,
            shieldInstaller: ShieldInstaller(
                fileExists: { _ in true },
                bundledServer: URL(fileURLWithPath: "/server"),
                bundledPlugin: URL(fileURLWithPath: "/plugin")
            ),
            isShieldInstalled: { true }
        )
        await installer.start()
        XCTAssertEqual(installer.steps[.botCheckShield], .done)
        XCTAssertEqual(installer.steps[.testRun], .done)
        XCTAssertTrue(installer.canProceedToHome)
        XCTAssertEqual(probe.probedURLs.last, CanaryProbe.url)
    }

    func test_toolsMissing_blocksWithoutInstallingAnything() async {
        let runner = FakeProcessRunner()
        let installer = OnboardingInstaller(
            probe: FakeEnvironmentProbe(.with()),
            runner: runner,
            isShieldInstalled: { false }
        )
        await installer.start()
        XCTAssertFalse(installer.canProceedToHome)
        XCTAssertTrue(runner.launches.isEmpty)
        guard case .failed = installer.steps[.testRun] else {
            return XCTFail("expected the check to fail, got \(String(describing: installer.steps[.testRun]))")
        }
    }

    func test_canaryFailure_marksTheCheckFailed() async {
        let installer = OnboardingInstaller(
            probe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
            runner: FakeProcessRunner(),
            metadataProbe: FakeMetadataProbe(default: .failure(.network))
        )
        await installer.start()
        guard case .failed = installer.steps[.testRun] else {
            return XCTFail("expected the check to fail")
        }
    }

    func test_check_readyTools_marksTheCheckDoneWithoutInstalling() async {
        let runner = FakeProcessRunner()
        let installer = OnboardingInstaller(
            probe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
            runner: runner,
            metadataProbe: FakeMetadataProbe(default: FakeMetadataProbe.success(title: "ok")),
            isShieldInstalled: { true }
        )
        await installer.check()
        XCTAssertEqual(installer.steps[.botCheckShield], .skipped)
        XCTAssertEqual(installer.steps[.testRun], .done)
        XCTAssertTrue(installer.canProceedToHome)
        XCTAssertTrue(runner.launches.isEmpty)
    }

    func test_check_shieldMissing_isOfferedNotInstalled() async {
        let runner = FakeProcessRunner()
        let installer = OnboardingInstaller(
            probe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
            runner: runner,
            metadataProbe: FakeMetadataProbe(default: FakeMetadataProbe.success(title: "ok")),
            isShieldInstalled: { false }
        )
        await installer.check()
        XCTAssertEqual(installer.steps[.botCheckShield], .pending)
        XCTAssertTrue(installer.canProceedToHome)
        XCTAssertTrue(runner.launches.isEmpty)
    }
}
