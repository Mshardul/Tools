@testable import GrabberKit
@testable import MediaGrabber
import TestSupport
import XCTest

@MainActor
final class ShieldSetupControllerTests: XCTestCase {
    private func installer(
        runner: FakeProcessRunner = FakeProcessRunner(),
        alreadyBuilt: Bool = true,
        nodeInstalled: Bool = true,
        brew: Bool = true
    ) -> ShieldInstaller {
        ShieldInstaller(
            runner: runner,
            home: URL(fileURLWithPath: "/Users/tester"),
            isExecutable: {
                ($0 == "/opt/homebrew/bin/node" && nodeInstalled) || ($0 == "/opt/homebrew/bin/brew" && brew)
            },
            fileExists: { _ in alreadyBuilt },
            prepareDirectory: { _ in },
            removeItem: { _ in }
        )
    }

    private func controller(
        installer: ShieldInstaller? = nil,
        restartResult: Bool = true,
        opener: FakeOpenURLSink = FakeOpenURLSink()
    ) -> ShieldSetupController {
        ShieldSetupController(installer: installer ?? self.installer(), restart: { restartResult }, openURL: opener)
    }

    func test_success_startsShieldClearsPromptAndNotifies() async {
        let sut = controller()
        sut.probePrompt = .setUp
        var notified = false
        sut.onInstalled = { notified = true }
        await sut.run()
        XCTAssertEqual(sut.state, .done)
        XCTAssertNil(sut.probePrompt)
        XCTAssertTrue(notified)
    }

    func test_installedButShieldDoesNotStart_isNotReportedAsDone() async {
        let sut = controller(restartResult: false)
        await sut.run()
        XCTAssertEqual(sut.state, .failed(detail: "installed, but the shield did not start"))
    }

    func test_installFailure_isReported() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout("v24.8.0"), forPathEndingIn: "node")
        runner.script(.stderr("curl: (6) Could not resolve host\n"), forPathEndingIn: "curl")
        let sut = controller(installer: installer(runner: runner, alreadyBuilt: false))
        await sut.run()
        XCTAssertEqual(sut.state, .failed(detail: "download: curl: (6) Could not resolve host\n"))
    }

    func test_missingHomebrew_pointsToHomebrewSite() async {
        let opener = FakeOpenURLSink()
        let sut = controller(
            installer: installer(alreadyBuilt: false, nodeInstalled: false, brew: false), opener: opener
        )
        await sut.run()
        XCTAssertEqual(sut.state, .needsHomebrew)
        sut.openHomebrewSite()
        XCTAssertEqual(opener.opened.map(\.absoluteString), ["https://brew.sh"])
    }

    func test_presentResetsFinishedStateAndShowsSheet() async {
        let sut = controller(restartResult: false)
        await sut.run()
        sut.present()
        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(sut.isPresented)
    }

    func test_copyNeverContainsCommandsOrJargon() {
        let states: [ShieldSetupController.State] = [
            .idle, .working(""), .done, .needsHomebrew, .failed(detail: "x")
        ]
        for state in states {
            let text = ShieldSetupSheet.explanation(for: state).lowercased()
            for banned in ["pipx", "brew install", "yt-dlp", "pot", "cookie"] {
                XCTAssertFalse(text.contains(banned), "\(state): \(banned)")
            }
        }
    }
}
