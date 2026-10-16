@testable import GrabberKit
import TestSupport
import XCTest

@MainActor
final class OnboardingInstallerTests: XCTestCase {
    private func installer(
        probe: FakeEnvironmentProbe,
        runner: FakeProcessRunner
    ) -> OnboardingInstaller {
        OnboardingInstaller(
            probe: probe,
            runner: runner,
            shieldInstaller: ShieldInstaller(
                runner: runner, isExecutable: { _ in false }, fileExists: { _ in false },
                prepareDirectory: { _ in }, removeItem: { _ in }
            ),
            isShieldInstalled: { false }
        )
    }

    private func brewURL() -> URL {
        URL(fileURLWithPath: "/opt/homebrew/bin/brew")
    }

    func test_allPresent_skipsToProceed() async {
        let probe = FakeEnvironmentProbe(.with(brew: true, ytDlp: true, ffmpeg: true))
        let runner = FakeProcessRunner()
        let sut = installer(probe: probe, runner: runner)
        await sut.start()
        XCTAssertEqual(sut.steps[.homebrew], .skipped)
        XCTAssertTrue(
            sut.steps[.downloaderTools] == .skipped
                || sut.steps[.downloaderTools] == .done
        )
        XCTAssertTrue(sut.canProceedToHome)
    }

    func test_toolsMissing_brewPresent_installsThenProceeds() async {
        // 1st probe: brew only. 2nd probe (after `brew install`): all present.
        let probe = FakeEnvironmentProbe(
            .with(brew: true),
            .with(brew: true, ytDlp: true, ffmpeg: true)
        )
        let runner = FakeProcessRunner()
        runner.script(
            .stdout("==> Downloading\n==> Pouring yt-dlp\n==> Pouring ffmpeg\n"),
            forPathEndingIn: "brew"
        )
        let sut = installer(probe: probe, runner: runner)
        await sut.start()

        XCTAssertEqual(sut.steps[.downloaderTools], .done)
        XCTAssertTrue(sut.canProceedToHome)
    }

    func test_brewMissing_blocksWithCommand() async {
        let probe = FakeEnvironmentProbe(.with())
        let runner = FakeProcessRunner()
        let sut = installer(probe: probe, runner: runner)
        await sut.start()

        guard case let .failed(reason) = sut.steps[.homebrew] else {
            return XCTFail(
                "expected .homebrew failed, got \(String(describing: sut.steps[.homebrew]))"
            )
        }
        XCTAssertTrue(reason.contains(HomebrewInstallInfo.command))
        XCTAssertFalse(sut.canProceedToHome)
        XCTAssertTrue(runner.launches.isEmpty, "no brew install should be attempted")
    }

    func test_recheck_afterBrewInstalled_resumes() async {
        let probe = FakeEnvironmentProbe(.with())
        let runner = FakeProcessRunner()
        runner.script(.stdout("==> Pouring\n"), forPathEndingIn: "brew")
        let sut = installer(probe: probe, runner: runner)
        await sut.start()
        XCTAssertFalse(sut.canProceedToHome)

        probe.setReports(
            .with(brew: true),
            .with(brew: true, ytDlp: true, ffmpeg: true)
        )
        await sut.recheck()

        XCTAssertTrue(sut.canProceedToHome)
    }

    func test_botCheckShieldFailure_doesNotBlock() async {
        let probe = FakeEnvironmentProbe(.with(brew: true, ytDlp: true, ffmpeg: true))
        let runner = FakeProcessRunner()
        runner.script(.stderr("could not find pipx\n"), forPathEndingIn: "pipx")
        let sut = installer(probe: probe, runner: runner)
        await sut.start()

        if case .failed = sut.steps[.botCheckShield] {
            // acceptable
        } else {
            XCTAssertEqual(sut.steps[.botCheckShield], .skipped)
        }
        XCTAssertTrue(sut.canProceedToHome)
    }

    func test_downloaderInstallFailure_surfacesReasonAndBlocks() async {
        let probe = FakeEnvironmentProbe(.with(brew: true))
        let runner = FakeProcessRunner()
        runner.script(
            .stderr("Error: Cannot install yt-dlp\nsome detail line\n", exitCode: 1),
            forPathEndingIn: "brew"
        )
        let sut = installer(probe: probe, runner: runner)
        await sut.start()

        guard case let .failed(reason) = sut.steps[.downloaderTools] else {
            return XCTFail("expected downloaderTools failed")
        }
        XCTAssertTrue(reason.contains("Cannot install yt-dlp") || reason
            .contains("some detail line"))
        XCTAssertFalse(sut.canProceedToHome)
    }

    func test_testRunStep_realProbeSucceeds_marksStepDone() async {
        let fakeMetadataProbe = FakeMetadataProbe(default: FakeMetadataProbe.success(title: "Big Buck Bunny"))
        let installer = OnboardingInstaller(
            probe: FakeEnvironmentProbe(.with(brew: true, ytDlp: true, ffmpeg: true)),
            runner: FakeProcessRunner(),
            metadataProbe: fakeMetadataProbe
        )
        await installer.start()
        XCTAssertEqual(installer.steps[.testRun], .done)
    }

    func test_testRunStep_probeFails_marksStepFailed() async {
        let fakeMetadataProbe = FakeMetadataProbe(default: .failure(.network))
        let installer = OnboardingInstaller(
            probe: FakeEnvironmentProbe(.with(brew: true, ytDlp: true, ffmpeg: true)),
            runner: FakeProcessRunner(),
            metadataProbe: fakeMetadataProbe
        )
        await installer.start()
        if case .failed = installer.steps[.testRun] {
            // acceptable
        } else {
            XCTFail("expected .testRun failed, got \(String(describing: installer.steps[.testRun]))")
        }
    }

    func test_testRunStep_probesTheKnownCanaryURL() async {
        let fakeMetadataProbe = FakeMetadataProbe(default: FakeMetadataProbe.success(title: "Big Buck Bunny"))
        let installer = OnboardingInstaller(
            probe: FakeEnvironmentProbe(.with(brew: true, ytDlp: true, ffmpeg: true)),
            runner: FakeProcessRunner(),
            metadataProbe: fakeMetadataProbe
        )
        await installer.start()
        XCTAssertEqual(fakeMetadataProbe.probedURLs.last, CanaryProbe.url)
    }

    // MARK: - check(): report what is already in place without installing anything

    func test_check_everythingPresent_marksStepsAlreadyDone_andInstallsNothing() async {
        let probe = FakeEnvironmentProbe(.with(brew: true, ytDlp: true, ffmpeg: true))
        let runner = FakeProcessRunner()
        let sut = OnboardingInstaller(
            probe: probe, runner: runner, metadataProbe: AlwaysOKProbe(), isShieldInstalled: { true }
        )
        await sut.check()
        XCTAssertEqual(sut.steps[.homebrew], .skipped)
        XCTAssertEqual(sut.steps[.downloaderTools], .skipped)
        XCTAssertEqual(sut.steps[.botCheckShield], .skipped)
        XCTAssertEqual(sut.steps[.testRun], .done)
        XCTAssertTrue(sut.canProceedToHome)
        XCTAssertTrue(runner.launches.isEmpty)
    }

    func test_check_shieldMissing_isOfferedNotInstalled() async {
        let probe = FakeEnvironmentProbe(.with(brew: true, ytDlp: true, ffmpeg: true))
        let runner = FakeProcessRunner()
        let sut = OnboardingInstaller(
            probe: probe, runner: runner, metadataProbe: AlwaysOKProbe(), isShieldInstalled: { false }
        )
        await sut.check()
        XCTAssertEqual(sut.steps[.botCheckShield], .pending)
        XCTAssertTrue(sut.canProceedToHome)
        XCTAssertTrue(runner.launches.isEmpty)
    }

    func test_check_toolsMissing_blocksContinue_andInstallsNothing() async {
        let probe = FakeEnvironmentProbe(.with(brew: true))
        let runner = FakeProcessRunner()
        let sut = OnboardingInstaller(probe: probe, runner: runner, isShieldInstalled: { false })
        await sut.check()
        XCTAssertEqual(sut.steps[.downloaderTools], .pending)
        XCTAssertEqual(sut.steps[.testRun], .pending)
        XCTAssertFalse(sut.canProceedToHome)
        XCTAssertTrue(runner.launches.isEmpty)
    }

    func test_check_homebrewMissing_showsTheInstallCommand() async {
        let probe = FakeEnvironmentProbe(.with())
        let sut = OnboardingInstaller(probe: probe, runner: FakeProcessRunner(), isShieldInstalled: { false })
        await sut.check()
        XCTAssertEqual(sut.steps[.homebrew], .failed(reason: HomebrewInstallInfo.command))
    }

    func test_installProgress_neverShowsRawToolOutput() async {
        let probe = FakeEnvironmentProbe(.with(brew: true), .with(brew: true, ytDlp: true, ffmpeg: true))
        let runner = FakeProcessRunner()
        runner.script(.stdout("==> Pouring python@3.15--3.15.0.bottle.tar.gz"), forPathEndingIn: "brew")
        let sut = installer(probe: probe, runner: runner)
        await sut.start()
        for case let .running(text) in sut.steps.values {
            XCTAssertFalse(text.contains("Pouring"))
        }
    }
}

private struct AlwaysOKProbe: MetadataProbing {
    typealias ProbeResult = Result<MediaMetadata, MetadataError>

    func probe(
        _: String,
        context _: ExtractorContext,
        onWait _: (@Sendable (Date?) -> Void)?
    ) async -> ProbeResult {
        .success(MediaMetadata(title: "t", durationSeconds: 1, isPlaylist: false, sourceURL: "u"))
    }

    func probePlaylist(_: String, context _: ExtractorContext) async -> Result<PlaylistDump, MetadataError> {
        .failure(.malformedOutput)
    }
}
