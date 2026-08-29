import Foundation
import Observation

#if canImport(AppKit)
    import AppKit
#endif

public enum OnboardingStepID: Sendable, CaseIterable {
    case homebrew
    case downloaderTools
    case botCheckShield
    case testRun
}

public enum OnboardingStepState: Sendable, Equatable {
    case pending
    case running(text: String)
    case done
    case failed(reason: String)
    case skipped
}

public enum HomebrewInstallInfo: Sendable {
    public static let command =
        "/bin/bash -c \"$(curl -fsSL "
            + "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
}

@MainActor
@Observable
public final class OnboardingInstaller {
    public private(set) var steps: [OnboardingStepID: OnboardingStepState]
    public private(set) var canProceedToHome: Bool

    private let probe: EnvironmentProbing
    private let runner: ProcessRunning

    public init(
        probe: EnvironmentProbing = EnvironmentProbe(),
        runner: ProcessRunning = ProcessRunner()
    ) {
        self.probe = probe
        self.runner = runner
        steps = Dictionary(
            uniqueKeysWithValues: OnboardingStepID.allCases.map { ($0, .pending) }
        )
        canProceedToHome = false
    }

    public func start() async {
        await runFlow()
    }

    public func recheck() async {
        await runFlow()
    }

    public func openTerminalForHomebrew() {
        #if canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(HomebrewInstallInfo.command, forType: .string)
            if let terminal = URL(string: "file:///System/Applications/Utilities/Terminal.app") {
                NSWorkspace.shared.open(terminal)
            }
        #endif
    }

    private func runFlow() async {
        var report = await probe.probe()
        canProceedToHome = report.isReadyForDownloads

        guard let brew = report.brew else {
            steps[.homebrew] = .failed(reason: HomebrewInstallInfo.command)
            canProceedToHome = false
            return
        }
        steps[.homebrew] = .skipped

        if report.isReadyForDownloads {
            steps[.downloaderTools] = .skipped
        } else {
            let outcome = await runStreaming(
                step: .downloaderTools,
                launch: ProcessLaunch(
                    executableURL: brew.path,
                    arguments: ["install", "yt-dlp", "ffmpeg"]
                )
            )
            if case .failed = outcome {
                steps[.downloaderTools] = outcome
                canProceedToHome = false
                return
            }
            report = await probe.probe()
            guard report.isReadyForDownloads else {
                steps[.downloaderTools] = .failed(
                    reason: "yt-dlp / ffmpeg still not found after install"
                )
                canProceedToHome = false
                return
            }
            steps[.downloaderTools] = .done
        }
        canProceedToHome = report.isReadyForDownloads

        steps[.botCheckShield] = await runStreaming(
            step: .botCheckShield,
            launch: pipxLaunch(["install", "bgutil-ytdlp-pot-provider"])
        )

        // TODO(Task 11): real canary probe of a known-stable URL.
        steps[.testRun] = canProceedToHome ? .done : .pending
    }

    private func runStreaming(
        step: OnboardingStepID,
        launch: ProcessLaunch
    ) async -> OnboardingStepState {
        steps[step] = .running(text: "")
        let execution = runner.run(launch)
        var stderrTail: [String] = []
        for await line in execution.lines {
            switch line {
            case let .stdout(text):
                steps[step] = .running(text: text)
            case let .stderr(text):
                steps[step] = .running(text: text)
                stderrTail.append(text)
                if stderrTail.count > 5 {
                    stderrTail.removeFirst()
                }
            }
        }
        let result = await execution.result()
        if result.exitCode == 0 {
            return .done
        }
        let reason = stderrTail.isEmpty
            ? "exited \(result.exitCode)"
            : stderrTail.joined(separator: "\n")
        return .failed(reason: reason)
    }

    private func pipxLaunch(_ args: [String]) -> ProcessLaunch {
        let path = ["/opt/homebrew/bin/pipx", "/usr/local/bin/pipx", "/usr/bin/pipx"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "/opt/homebrew/bin/pipx"
        return ProcessLaunch(executableURL: URL(fileURLWithPath: path), arguments: args)
    }
}
