@testable import GrabberKit
import XCTest

@MainActor
final class DownloadEngineTests: XCTestCase {
    private let ytDlp = URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp")

    private func request(
        url: String = "https://archive.org/details/x",
        destFolder: URL = URL(fileURLWithPath: NSTemporaryDirectory())
    ) -> DownloadRequest {
        DownloadRequest(
            url: url,
            destFolder: destFolder,
            kind: .video(maxHeight: 1080),
            container: "mp4"
        )
    }

    private func engine(
        runner: FakeProcessRunner,
        probe: FakeMetadataProbe
    ) -> DownloadEngine {
        DownloadEngine(ytDlpURL: ytDlp, runner: runner, probe: probe)
    }

    private func progressLine(_ percent: String) -> ProcessLine {
        .stdout("MG|\(percent)|1.00MiB/s|00:10|100|1000")
    }

    private func waitUntilTerminal(
        _ job: DownloadJob,
        timeout: TimeInterval = 5
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch job.state {
            case .completed, .cancelled, .failed:
                return
            default:
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    func test_submitReturnsQueuedImmediately() async {
        let runner = FakeProcessRunner()
        let probe = FakeMetadataProbe()
        probe.perProbeDelay = .milliseconds(200)
        let sut = engine(runner: runner, probe: probe)

        let job = await sut.submit(request())

        XCTAssertEqual(job.state, .queued)
        XCTAssertFalse(probe.wasProbed)
        XCTAssertTrue(runner.launches.isEmpty)
    }

    func test_happyPath_timeline() async {
        let runner = FakeProcessRunner()
        runner.script(
            FakeProcessRunner.Script(
                lines: [progressLine(" 25.0%"), progressLine(" 60.0%"), progressLine("100.0%")],
                exitCode: 0
            ),
            forPathEndingIn: "yt-dlp"
        )
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let sut = engine(runner: runner, probe: probe)

        let job = await sut.submit(request())
        await waitUntilTerminal(job)

        XCTAssertEqual(job.state, .completed)
        XCTAssertEqual(job.title, "Clip")
        XCTAssertEqual(job.progress?.fraction, 1.0)
        XCTAssertNotNil(job.finishedAt)
    }

    func test_stateSequence() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .milliseconds(40)
        runner.script(.stdout("", exitCode: 0), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.perProbeDelay = .milliseconds(40)
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let sut = engine(runner: runner, probe: probe)

        let job = await sut.submit(request())
        var seen: [JobState] = [job.state]
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if seen.last != job.state {
                seen.append(job.state)
            }
            if case .completed = job.state {
                break
            }
            try? await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(seen, [.queued, .probing, .running, .completed])
    }

    func test_progressUpdatesAreObservable() async {
        let runner = FakeProcessRunner()
        runner.perLineDelay = .milliseconds(20)
        runner.script(
            FakeProcessRunner.Script(
                lines: [progressLine(" 25.0%"), progressLine(" 60.0%"), progressLine("100.0%")],
                exitCode: 0
            ),
            forPathEndingIn: "yt-dlp"
        )
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let sut = engine(runner: runner, probe: probe)

        let job = await sut.submit(request())
        var fractions: [Double] = []
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let fraction = job.progress?.fraction, fractions.last != fraction {
                fractions.append(fraction)
            }
            if case .completed = job.state {
                break
            }
            try? await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(fractions, [0.25, 0.6, 1.0])
    }

    func test_nonZeroExit_withNetworkStderr_failsNetworkDown() async {
        let runner = FakeProcessRunner()
        runner.script(
            FakeProcessRunner.Script(
                lines: [.stderr(
                    "ERROR: Unable to download webpage: Failed to resolve 'x' "
                        + "(nodename nor servname provided, or not known)"
                )],
                exitCode: 1
            ),
            forPathEndingIn: "yt-dlp"
        )
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let sut = engine(runner: runner, probe: probe)

        let job = await sut.submit(request())
        await waitUntilTerminal(job)

        XCTAssertEqual(job.state, .failed(.networkDown))
    }

    func test_nonZeroExit_noStderrSignature_failsUnknown() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout("", exitCode: 3), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let sut = engine(runner: runner, probe: probe)

        let job = await sut.submit(request())
        await waitUntilTerminal(job)

        guard case let .failed(.unknown(raw)) = job.state else {
            return XCTFail("expected .failed(.unknown), got \(job.state)")
        }
        XCTAssertTrue(raw.contains("3"))
    }

    func test_probeNetworkFailure_failsBeforeSpawning() async {
        let runner = FakeProcessRunner()
        let probe = FakeMetadataProbe()
        probe.result(.failure(.network))
        let sut = engine(runner: runner, probe: probe)

        let job = await sut.submit(request())
        await waitUntilTerminal(job)

        XCTAssertEqual(job.state, .failed(.networkDown))
        XCTAssertTrue(runner.launches.isEmpty)
    }

    func test_probeYtDlpMissing_failsDepMissing() async {
        let runner = FakeProcessRunner()
        let probe = FakeMetadataProbe()
        probe.result(.failure(.ytDlpMissing))
        let sut = engine(runner: runner, probe: probe)

        let job = await sut.submit(request())
        await waitUntilTerminal(job)

        XCTAssertEqual(job.state, .failed(.depMissing))
        XCTAssertTrue(runner.launches.isEmpty)
    }

    func test_cancel_killsChildAndSetsCancelled() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(30)
        runner.script(.stdout("", exitCode: 0), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let sut = engine(runner: runner, probe: probe)

        let job = await sut.submit(request())
        // Wait until the child is actually spawned.
        let spawnDeadline = Date().addingTimeInterval(5)
        while Date() < spawnDeadline, runner.launches.isEmpty {
            try? await Task.sleep(for: .milliseconds(5))
        }
        await sut.cancel(job.id)
        await waitUntilTerminal(job)

        XCTAssertEqual(job.state, .cancelled)
        XCTAssertEqual(runner.cancelledCount, 1)
        XCTAssertNotNil(job.finishedAt)
    }

    func test_cancelQueuedJob_neverRuns() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .milliseconds(300)
        runner.script(.stdout("", exitCode: 0), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let sut = engine(runner: runner, probe: probe)

        let first = await sut.submit(request(url: "https://archive.org/details/1"))
        let second = await sut.submit(request(url: "https://archive.org/details/2"))
        await sut.cancel(second.id)

        await waitUntilTerminal(first)
        await waitUntilTerminal(second)

        let secondURL = "https://archive.org/details/2"
        XCTAssertEqual(second.state, .cancelled)
        XCTAssertFalse(
            probe.probedURLs.contains(secondURL),
            "cancelled queued job must never be probed or run"
        )
        XCTAssertTrue(runner.launches.allSatisfy { $0.arguments.last != secondURL })
    }

    func test_twoJobsRunFIFONoOverlap() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .milliseconds(80)
        runner.script(.stdout("", exitCode: 0), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let sut = engine(runner: runner, probe: probe)

        let first = await sut.submit(request(url: "https://archive.org/details/1"))
        let second = await sut.submit(request(url: "https://archive.org/details/2"))
        await waitUntilTerminal(first)
        await waitUntilTerminal(second)

        XCTAssertEqual(runner.maxConcurrent, 1)
        XCTAssertEqual(first.state, .completed)
        XCTAssertEqual(second.state, .completed)
    }

    func test_outputFilesResolvedOnCompletion() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-engine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Clip.mp4")
        try Data("x".utf8).write(to: file)

        let runner = FakeProcessRunner()
        runner.script(.stdout("", exitCode: 0), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let sut = engine(runner: runner, probe: probe)

        let job = await sut.submit(request(destFolder: dir))
        await waitUntilTerminal(job)

        XCTAssertEqual(job.state, .completed)
        XCTAssertEqual(job.outputFiles.map(\.lastPathComponent), ["Clip.mp4"])
    }
}
