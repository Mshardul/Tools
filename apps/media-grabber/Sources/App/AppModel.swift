import Foundation
import GrabberKit
import Observation

#if canImport(AppKit)
    import AppKit
#endif

@MainActor
protocol RevealSink {
    func reveal(_ files: [URL])
}

struct WorkspaceRevealSink: RevealSink {
    func reveal(_ files: [URL]) {
        #if canImport(AppKit)
            guard !files.isEmpty else { return }
            NSWorkspace.shared.activateFileViewerSelecting(files)
        #endif
    }
}

@MainActor
@Observable
final class AppModel {
    enum Page {
        case home
        case preferences
        case diagnostics
    }

    var page: Page = .home
    private(set) var needsOnboarding = false
    private(set) var job: DownloadJob?
    private(set) var resolved: MediaMetadata?
    private(set) var probeError: String?
    private(set) var isProbing = false

    let installer: OnboardingInstaller
    let prefs: Preferences

    private let engine: DownloadEngineProtocol
    private let probe: MetadataProbing
    private let envProbe: EnvironmentProbing
    private let log: LogWriter
    private let forceOnboarding: Bool
    private let revealSink: RevealSink

    init(
        engine: DownloadEngineProtocol,
        probe: MetadataProbing,
        installer: OnboardingInstaller,
        prefs: Preferences,
        log: LogWriter,
        envProbe: EnvironmentProbing = EnvironmentProbe(),
        forceOnboarding: Bool = false,
        revealSink: RevealSink = WorkspaceRevealSink()
    ) {
        self.engine = engine
        self.probe = probe
        self.installer = installer
        self.prefs = prefs
        self.log = log
        self.envProbe = envProbe
        self.forceOnboarding = forceOnboarding
        self.revealSink = revealSink
    }

    func onAppear() async {
        await log.log(.appLaunched)
        await refreshOnboardingState()
    }

    func refreshOnboardingState() async {
        if forceOnboarding {
            needsOnboarding = true
            return
        }
        let report = await envProbe.probe()
        needsOnboarding = !report.isReadyForDownloads
    }

    func onboardingFinished() {
        needsOnboarding = false
    }

    func resolvePasted(_ url: String) async {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isProbing = true
        probeError = nil
        let result = await probe.probe(trimmed)
        isProbing = false
        switch result {
        case let .success(meta):
            resolved = meta
            await log.log(.probeCompleted(url: trimmed, title: meta.title, ok: true))
        case let .failure(error):
            resolved = nil
            probeError = Self.message(for: error)
            await log.log(.probeCompleted(url: trimmed, title: nil, ok: false))
        }
    }

    func clearResolved() {
        resolved = nil
        probeError = nil
    }

    func grab() async {
        guard let resolved else { return }
        let request = DownloadRequest(
            url: resolved.sourceURL,
            destFolder: prefs.lastUsedDestFolder,
            kind: prefs.defaultKind,
            container: containerForCurrentKind()
        )
        job = await engine.submit(request)
    }

    func reveal() {
        guard let job else { return }
        revealSink.reveal(job.outputFiles)
    }

    func cancelJob() async {
        guard let job else { return }
        await engine.cancel(job.id)
    }

    private func containerForCurrentKind() -> String? {
        if case .video = prefs.defaultKind {
            return "mp4"
        }
        return nil
    }

    private static func message(for error: MetadataError) -> String {
        switch error {
        case .badURL: "That doesn't look like a valid link."
        case .unsupported: "That site isn't supported."
        case .unavailable: "This video isn't available."
        case .network: "No internet connection."
        case .ytDlpMissing: "yt-dlp is missing — reopen setup."
        case .malformedOutput: "Couldn't read the video details."
        case let .unknown(raw): raw
        }
    }
}
