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
    private let injectedMetadataProbe: MetadataProbing?
    private let shieldInstaller: ShieldInstaller
    private let isShieldInstalled: @Sendable () -> Bool

    public init(
        probe: EnvironmentProbing = EnvironmentProbe(),
        runner: ProcessRunning = ProcessRunner(),
        metadataProbe: MetadataProbing? = nil,
        shieldInstaller: ShieldInstaller? = nil,
        isShieldInstalled: (@Sendable () -> Bool)? = nil
    ) {
        self.probe = probe
        self.runner = runner
        self.isShieldInstalled = isShieldInstalled ?? {
            PotPluginInstaller.live().resolveServerLaunch(port: 0) != nil
        }
        self.shieldInstaller = shieldInstaller ?? ShieldInstaller(runner: runner)
        injectedMetadataProbe = metadataProbe
        steps = Dictionary(
            uniqueKeysWithValues: OnboardingStepID.allCases.map { ($0, .pending) }
        )
        canProceedToHome = false
    }

    public func start() async {
        await runFlow()
    }

    // Reports what is already in place without installing anything.
    public func check() async {
        let report = await probe.probe()
        canProceedToHome = report.isReadyForDownloads
        guard report.brew != nil else {
            steps[.homebrew] = .failed(reason: HomebrewInstallInfo.command)
            steps[.downloaderTools] = report.isReadyForDownloads ? .skipped : .pending
            steps[.botCheckShield] = isShieldInstalled() ? .skipped : .pending
            steps[.testRun] = .pending
            return
        }
        steps[.homebrew] = .skipped
        steps[.downloaderTools] = report.isReadyForDownloads ? .skipped : .pending
        steps[.botCheckShield] = isShieldInstalled() ? .skipped : .pending
        steps[.testRun] = report.isReadyForDownloads
            ? await runCanaryProbe(ytDlpPath: report.ytDlp?.path)
            : .pending
    }

    public func installShieldOnly() async {
        steps[.botCheckShield] = await installShield()
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

        steps[.botCheckShield] = await installShield()

        steps[.testRun] = await runCanaryProbe(ytDlpPath: report.ytDlp?.path)
    }

    private func runCanaryProbe(ytDlpPath: URL?) async -> OnboardingStepState {
        guard canProceedToHome else {
            return .pending
        }
        let result: Result<MediaMetadata, MetadataError> = if let injectedMetadataProbe {
            await injectedMetadataProbe.probe(CanaryProbe.url)
        } else {
            await CanaryProbe.run(ytDlpPath: ytDlpPath, runner: runner)
        }
        switch result {
        case .success:
            return .done
        case let .failure(error):
            return .failed(reason: "\(error)")
        }
    }

    private func runStreaming(
        step: OnboardingStepID,
        launch: ProcessLaunch
    ) async -> OnboardingStepState {
        steps[step] = .running(text: "Installing \u{2014} this can take a few minutes.")
        let execution = runner.run(launch)
        var stderrTail: [String] = []
        for await line in execution.lines {
            switch line {
            case .stdout:
                break
            case let .stderr(text):
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

    private func installShield() async -> OnboardingStepState {
        steps[.botCheckShield] = .running(text: "Starting\u{2026}")
        let outcome = await shieldInstaller.install { [weak self] text in
            Task { @MainActor in self?.steps[.botCheckShield] = .running(text: text) }
        }
        switch outcome {
        case .installed:
            return .done
        case .needsHomebrew:
            return .failed(reason: "Setting this up needs Homebrew first.")
        case .failed:
            return .failed(reason: "Setup didn't finish. You can try again later from the top of the window.")
        }
    }
}
