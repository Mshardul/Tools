@testable import GrabberKit
import TestSupport
import XCTest

final class FakeProcessRunnerTests: XCTestCase {
    private func launch(_ name: String) -> ProcessLaunch {
        let url = URL(fileURLWithPath: "/opt/homebrew/bin/\(name)")
        return ProcessLaunch(executableURL: url, arguments: [])
    }

    private func drain(_ exec: ProcessExecution) async -> ProcessResult {
        for await _ in exec.lines {}
        return await exec.result()
    }

    func testOrderedScriptsAdvancePerLaunch() async {
        let runner = FakeProcessRunner()
        let scripts: [FakeProcessRunner.Script] = [
            .stderr("ERROR: HTTP Error 429", exitCode: 1),
            FakeProcessRunner.Script(exitCode: 0)
        ]

        runner.scripts(scripts, forPathEndingIn: "yt-dlp")

        let first = await drain(runner.run(launch("yt-dlp")))
        XCTAssertEqual(first.exitCode, 1)
        let second = await drain(runner.run(launch("yt-dlp")))
        XCTAssertEqual(second.exitCode, 0)
    }

    func testLastOrderedScriptRepeats() async {
        let runner = FakeProcessRunner()
        runner.scripts([FakeProcessRunner.Script(exitCode: 3)], forPathEndingIn: "yt-dlp")
        _ = await drain(runner.run(launch("yt-dlp")))
        let again = await drain(runner.run(launch("yt-dlp")))
        XCTAssertEqual(again.exitCode, 3)
    }

    func testExactPathScriptWinsOverOrderedList() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout("exact", exitCode: 7), forExactPath: "/opt/homebrew/bin/yt-dlp")
        runner.scripts([
            .stderr("ERROR: HTTP Error 429", exitCode: 1),
            FakeProcessRunner.Script(exitCode: 0)
        ], forPathEndingIn: "yt-dlp")

        let first = await drain(runner.run(launch("yt-dlp")))
        let second = await drain(runner.run(launch("yt-dlp")))
        XCTAssertEqual(first.exitCode, 7)
        XCTAssertEqual(second.exitCode, 7)
    }

    func testSingleScriptApiUnchanged() async {
        let runner = FakeProcessRunner()
        runner.script(.stderr("ERROR: boom", exitCode: 1), forPathEndingIn: "yt-dlp")
        let first = await drain(runner.run(launch("yt-dlp")))
        let second = await drain(runner.run(launch("yt-dlp")))
        XCTAssertEqual(first.exitCode, 1)
        XCTAssertEqual(second.exitCode, 1)
    }
}
