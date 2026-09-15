import Foundation

public enum YtDlpUpdateResult: Sendable, Equatable {
    case success(newVersion: String)
    case failure(reason: String)
}

public protocol YtDlpUpdating: Sendable {
    func reinstallToMinimum() async -> YtDlpUpdateResult
}

public struct YtDlpUpdater: YtDlpUpdating {
    private let runner: ProcessRunning
    private let probe: EnvironmentProbing
    private let brewPath: URL

    public init(
        runner: ProcessRunning = ProcessRunner(),
        probe: EnvironmentProbing = EnvironmentProbe(),
        brewPath: URL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
    ) {
        self.runner = runner
        self.probe = probe
        self.brewPath = brewPath
    }

    public func reinstallToMinimum() async -> YtDlpUpdateResult {
        let execution = runner.run(ProcessLaunch(executableURL: brewPath, arguments: ["reinstall", "yt-dlp"]))
        var stderrOutput = ""
        for await line in execution.lines {
            if case let .stderr(text) = line {
                stderrOutput += text + "\n"
            }
        }
        let result = await execution.result()
        guard result.exitCode == 0 else {
            return .failure(reason: stderrOutput.isEmpty ? "brew reinstall yt-dlp failed" : stderrOutput)
        }
        let report = await probe.probe()
        guard let version = report.ytDlp?.version else {
            return .failure(reason: "yt-dlp not found after reinstall")
        }
        return .success(newVersion: version)
    }
}
