@testable import MediaGrabber
import XCTest

@MainActor
final class AppRelauncherTests: XCTestCase {
    func test_relaunch_buildsCommandWithExtraArguments() {
        let spy = SpyProcessLauncher()
        var terminateCalled = false
        let relauncher = AppRelauncher(launcher: spy) { terminateCalled = true }

        relauncher.relaunch(withExtraArguments: ["-MGForceOnboarding"])

        XCTAssertEqual(spy.launchedArguments, ["-MGForceOnboarding"])
        XCTAssertTrue(terminateCalled)
    }
}

final class SpyProcessLauncher: RelaunchProcessLaunching {
    private(set) var launchedArguments: [String] = []

    func launch(executablePath _: String, arguments: [String]) {
        launchedArguments = arguments
    }
}
