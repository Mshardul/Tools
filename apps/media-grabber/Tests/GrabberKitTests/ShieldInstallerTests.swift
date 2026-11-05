@testable import GrabberKit
import TestSupport
import XCTest

final class ShieldInstallerTests: XCTestCase {
    func test_bundledHelper_isReadyWithoutRunningAnything() async {
        let runner = FakeProcessRunner()
        let server = URL(fileURLWithPath: "/bundle/Shield/server/build/main.js")
        let plugin = URL(fileURLWithPath: "/bundle/Shield/plugin.zip")
        let installer = ShieldInstaller(
            runner: runner,
            fileExists: { $0 == server.path || $0 == plugin.path },
            bundledServer: server,
            bundledPlugin: plugin
        )
        let outcome = await installer.install()
        XCTAssertEqual(outcome, .installed)
        XCTAssertTrue(runner.launches.isEmpty)
    }

    func test_missingHelper_failsWithoutLookingOutsideTheApp() async {
        let runner = FakeProcessRunner()
        let installer = ShieldInstaller(
            runner: runner,
            fileExists: { _ in false },
            bundledServer: URL(fileURLWithPath: "/bundle/Shield/server/build/main.js"),
            bundledPlugin: URL(fileURLWithPath: "/bundle/Shield/plugin.zip")
        )
        let outcome = await installer.install()
        XCTAssertEqual(outcome, .failed(detail: "This copy of the app doesn't include the YouTube check."))
        XCTAssertTrue(runner.launches.isEmpty)
    }
}
