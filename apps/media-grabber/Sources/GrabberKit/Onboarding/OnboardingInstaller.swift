import Foundation
import Observation

public enum OnboardingStepID: Sendable, CaseIterable {
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

    private func runFlow() async {
        let report = await probe.probe()
        guard report.isReadyForDownloads else {
            canProceedToHome = false
            steps[.botCheckShield] = .pending
            steps[.testRun] = .failed(reason: "This copy of the app is missing its downloader.")
            return
        }
        canProceedToHome = true
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

    private func installShield() async -> OnboardingStepState {
        steps[.botCheckShield] = .running(text: "Starting\u{2026}")
        let outcome = await shieldInstaller.install { [weak self] text in
            Task { @MainActor in self?.steps[.botCheckShield] = .running(text: text) }
        }
        switch outcome {
        case .installed:
            return .done
        case .failed:
            return .failed(reason: "Setup didn't finish. You can try again later from the top of the window.")
        }
    }
}
