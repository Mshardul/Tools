@testable import GrabberKit
import XCTest

@MainActor
final class OnboardingInstallerTests: XCTestCase {
    private func installer(
        probe: FakeEnvironmentProbe,
        runner: FakeProcessRunner
    ) -> OnboardingInstaller {
        OnboardingInstaller(probe: probe, runner: runner)
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
}
