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
protocol OpenURLSink {
    func open(_ url: URL)
}

struct WorkspaceOpenURLSink: OpenURLSink {
    func open(_ url: URL) {
        #if canImport(AppKit)
            NSWorkspace.shared.open(url)
        #endif
    }
}

@MainActor
final class AppModelConfirmer: Confirming, @unchecked Sendable {
    weak var model: AppModel?

    func confirm(_ request: ConfirmationRequest) async -> Bool {
        guard let model else { return false }
        return await model.confirm(request)
    }
}

@MainActor
@Observable
final class AppModel {
    enum Page: Equatable {
        case home
        case preferences(PreferencesPane = .downloads)
        case diagnostics
    }

    var page: Page = .home {
        didSet {
            if page != .preferences(.cookies), pendingCookieRetryJobID != nil {
                pendingCookieRetryJobID = nil
            }
        }
    }

    private(set) var pendingCookieRetryJobID: UUID?
    private(set) var needsOnboarding = false
    private(set) var lastSubmittedJobID: UUID?
    private(set) var resolved: MediaMetadata?
    private(set) var probeError: String?
    private(set) var isProbing = false
    var pendingConfirmation: ConfirmationRequest?
    var scrollToRowID: UUID?
    var bannerContent: BannerContent?
    let debugFlags: DebugFlags

    var columnConfig: ColumnConfig = .default {
        didSet {
            guard columnConfig != oldValue else { return }
            rowStore.setColumnConfig(columnConfig)
            persistence?.saveColumns(columnConfig)
        }
    }

    let rowStore = RowStore()
    let installer: OnboardingInstaller
    let prefs: Preferences
    let quitCoordinator: QuitCoordinator

    var rows: [RowModel] {
        rowStore.rows
    }

    var healthChips: [HealthChip] {
        [HealthChip(id: "online", label: "online", dot: .ok, interaction: .none)]
    }

    var maxConcurrentDownloads: Int {
        debugFlags.concurrencyCapOverride ?? prefs.maxConcurrentDownloads
    }

    let engine: DownloadEngineProtocol
    private let probe: MetadataProbing
    private let envProbe: EnvironmentProbing
    let log: LogWriter
    private let persistence: (any QueuePersisting)?
    let revealSink: RevealSink
    let openURLSink: OpenURLSink
    let engineJobLogDir: URL
    private let suppression: SuppressionStore
    private var confirmationContinuation: CheckedContinuation<Bool, Never>?
    private var consumerTask: Task<Void, Never>?

    init(
        engine: DownloadEngineProtocol,
        probe: MetadataProbing,
        installer: OnboardingInstaller,
        prefs: Preferences,
        log: LogWriter,
        envProbe: EnvironmentProbing = EnvironmentProbe(),
        debugFlags: DebugFlags = DebugFlags(),
        revealSink: RevealSink = WorkspaceRevealSink(),
        openURLSink: OpenURLSink = WorkspaceOpenURLSink(),
        engineJobLogDir: URL = JobLog.defaultDir,
        suppression: SuppressionStore = UserDefaultsSuppressionStore(),
        persistence: (any QueuePersisting)? = nil,
        columnConfig: ColumnConfig = .default
    ) {
        self.engine = engine
        self.probe = probe
        self.installer = installer
        self.prefs = prefs
        self.log = log
        self.envProbe = envProbe
        self.debugFlags = debugFlags
        self.revealSink = revealSink
        self.openURLSink = openURLSink
        self.engineJobLogDir = engineJobLogDir
        self.suppression = suppression
        self.persistence = persistence
        self.columnConfig = columnConfig
        rowStore.setColumnConfig(columnConfig)
        let confirmer = AppModelConfirmer()
        quitCoordinator = QuitCoordinator(
            engine: engine,
            persistence: persistence ?? NoopPersisting(),
            confirmer: confirmer
        )
        confirmer.model = self
    }

    func onAppear() async {
        await log.log(.appLaunched)
        await performLaunchSetup()
        await refreshOnboardingState()
        startConsumerIfNeeded()
    }

    func performLaunchSetup() async {
        guard !debugFlags.resetState, let persistence else { return }
        let active = persistence.loadQueue()
        let history = persistence.loadHistory()
        await engine.restore(active: active, history: history)
        let snapshot = await engine.currentSnapshot()
        rowStore.resync(snapshot, maxAutoRetries: prefs.maxAutoRetries)
        applySnapshot(snapshot)
    }

    func refreshOnboardingState() async {
        if debugFlags.forceOnboarding {
            needsOnboarding = true
            return
        }
        let report = await envProbe.probe()
        needsOnboarding = !report.isReadyForDownloads
    }

    func onboardingFinished() async {
        await engine.revalidate()
        await refreshOnboardingState()
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
            probeError = AppModelDialogs.probeErrorMessage(for: error)
            await log.log(.probeCompleted(url: trimmed, title: nil, ok: false))
        }
    }

    func clearResolved() {
        resolved = nil
        probeError = nil
    }

    func grab(overrides: RunwayOverrides = RunwayOverrides()) async {
        guard let resolved else { return }
        let request = RequestBuilder.build(from: resolved, prefs: prefs, overrides: overrides)
        if let folder = overrides.destFolder {
            prefs.lastUsedDownloadFolder = folder
        }
        if let kind = overrides.kind {
            switch kind {
            case let .video(maxHeight):
                prefs.lastMediaType = .video
                prefs.lastVideoHeight = maxHeight
            case let .audio(format):
                prefs.lastMediaType = .audio
                prefs.lastAudioFormat = format
            }
        }

        let result = await engine.submit(request, force: false, prefetchedMetadata: resolved)
        switch result {
        case let .queued(id):
            lastSubmittedJobID = id
            scrollToRowID = id
        case let .duplicateExists(existing, wasCompleted):
            await log.log(.jobDuplicateSubmitPrompted(existing: existing))
            let confirmed = await confirm(AppModelDialogs
                .duplicateConfirmation(wasCompleted: wasCompleted))
            if confirmed {
                await log.log(.jobDuplicateSubmitConfirmed)
                let forced = await engine.submit(request, force: true, prefetchedMetadata: resolved)
                if case let .queued(id) = forced {
                    lastSubmittedJobID = id
                    scrollToRowID = id
                }
            } else {
                await log.log(.jobDuplicateSubmitCancelled)
                if wasCompleted {
                    scrollToRowID = existing
                }
            }
        }
    }

    func confirm(_ request: ConfirmationRequest) async -> Bool {
        if let key = request.suppressionKey, suppression.isSuppressed(key) {
            return true
        }
        pendingConfirmation = request
        return await withCheckedContinuation { continuation in
            confirmationContinuation = continuation
        }
    }

    func resolveConfirmation(_ confirmed: Bool, suppressFutures: Bool) {
        if confirmed, suppressFutures, let key = pendingConfirmation?.suppressionKey {
            suppression.setSuppressed(key)
        }
        pendingConfirmation = nil
        let continuation = confirmationContinuation
        confirmationContinuation = nil
        continuation?.resume(returning: confirmed)
    }

    func cancelJob() async {
        guard let id = lastSubmittedJobID else { return }
        await engine.cancel(id)
    }

    func resetAllSettings() {
        prefs.resetToDefaults()
    }

    func resolveCookieRetry() async {
        guard let id = pendingCookieRetryJobID else { return }
        pendingCookieRetryJobID = nil
        await engine.retryWithCookies(id)
    }

    func setPendingCookieRetry(_ id: UUID?) {
        pendingCookieRetryJobID = id
    }

    private func startConsumerIfNeeded() {
        guard consumerTask == nil else { return }
        consumerTask = Task { [weak self] in
            await self?.runConsumer()
        }
    }

    private func runConsumer() async {
        while !Task.isCancelled {
            for await event in engine.events {
                rowStore.apply(event, maxAutoRetries: prefs.maxAutoRetries)
                if case let .snapshot(snapshot) = event {
                    applySnapshot(snapshot)
                }
            }
            await log.log(.consumerStreamEnded)
            try? await Task.sleep(for: .seconds(1))
            await rowStore.resync(
                engine.currentSnapshot(),
                maxAutoRetries: prefs.maxAutoRetries
            )
        }
    }

    private func applySnapshot(_ snapshot: QueueSnapshot) {
        if snapshot.queueHalt == .depMissing {
            needsOnboarding = true
        }
    }
}
