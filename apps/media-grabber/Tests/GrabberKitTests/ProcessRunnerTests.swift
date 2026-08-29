@testable import GrabberKit
import XCTest

final class ProcessRunnerTests: XCTestCase {
    private let runner = ProcessRunner()

    private func launch(
        _ path: String,
        _ args: [String],
        env: [String: String]? = nil
    ) -> ProcessLaunch {
        ProcessLaunch(
            executableURL: URL(fileURLWithPath: path),
            arguments: args,
            environment: env
        )
    }

    private func collect(_ execution: ProcessExecution) async -> [ProcessLine] {
        var lines: [ProcessLine] = []
        for await line in execution.lines {
            lines.append(line)
        }
        return lines
    }

    private func fixtureURL(_ name: String, _ ext: String) throws -> URL {
        try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: ext),
            "missing fixture \(name).\(ext)"
        )
    }

    func test_true_exitsZero() async {
        let execution = runner.run(launch("/usr/bin/true", []))
        let lines = await collect(execution)
        let result = await execution.result()
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(lines.isEmpty)
        XCTAssertFalse(result.wasCancelled)
    }

    func test_false_exitsOne() async {
        let execution = runner.run(launch("/usr/bin/false", []))
        _ = await collect(execution)
        let result = await execution.result()
        XCTAssertEqual(result.exitCode, 1)
    }

    func test_echo_emitsStdoutLine() async {
        let execution = runner.run(launch("/bin/echo", ["hello"]))
        let lines = await collect(execution)
        let result = await execution.result()
        XCTAssertEqual(lines.count, 1)
        if case let .stdout(text) = lines.first {
            XCTAssertEqual(text, "hello")
        } else {
            XCTFail("expected one stdout line, got \(lines)")
        }
        XCTAssertEqual(result.exitCode, 0)
    }

    func test_stderr_isTaggedSeparately() async {
        let execution = runner.run(
            launch("/bin/sh", ["-c", "echo out; echo err 1>&2"])
        )
        let lines = await collect(execution)
        let stdout = lines.compactMap { line -> String? in
            if case let .stdout(text) = line {
                return text
            }
            return nil
        }
        let stderr = lines.compactMap { line -> String? in
            if case let .stderr(text) = line {
                return text
            }
            return nil
        }
        XCTAssertEqual(stdout, ["out"])
        XCTAssertEqual(stderr, ["err"])
    }

    func test_threeLines_arriveInOrder() async throws {
        let script = try fixtureURL("emit3lines", "sh")
        let execution = runner.run(launch("/bin/bash", [script.path]))
        let lines = await collect(execution)
        let stdout = lines.compactMap { line -> String? in
            if case let .stdout(text) = line {
                return text
            }
            return nil
        }
        XCTAssertEqual(stdout, ["line1", "line2", "line3"])
    }

    func test_cancellation_sendsSigtermAndReports() async throws {
        let script = try fixtureURL("hang", "sh")
        let start = Date()
        let runner = ProcessRunner()
        let launch = ProcessLaunch(
            executableURL: URL(fileURLWithPath: "/bin/bash"),
            arguments: [script.path]
        )
        let task = Task { () -> ProcessResult in
            let execution = runner.run(launch)
            for await _ in execution.lines {}
            return await execution.result()
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        let result = await task.value
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertTrue(result.wasCancelled)
        XCTAssertLessThan(elapsed, 5.0)
    }

    func test_environment_isPassedThrough() async {
        let execution = runner.run(
            launch("/bin/sh", ["-c", "echo $MG_TEST"], env: ["MG_TEST": "xyz"])
        )
        let lines = await collect(execution)
        let stdout = lines.compactMap { line -> String? in
            if case let .stdout(text) = line {
                return text
            }
            return nil
        }
        XCTAssertEqual(stdout, ["xyz"])
    }
}
