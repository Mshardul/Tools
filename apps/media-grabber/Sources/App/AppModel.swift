import Foundation
import GrabberKit
import Observation

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
    var resolved: ResolvedLink?
    var probeError: String?
    var isProbing = false
    var playlistGroups: [PersistedPlaylistGroup] = []
    var isPlaylistPickerPresented = false
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

    let healthController = HealthController()
    private(set) var hostRateSummary: [RateHost: HostRateDisplayState] = [:]

    var healthChips: [HealthChip] {
        healthController.chips
    }

    var resolvedVideo: MediaMetadata? {
        guard case let .video(meta) = resolved else { return nil }
        return meta
    }

    var maxConcurrentDownloads: Int {
        debugFlags.concurrencyCapOverride ?? prefs.maxConcurrentDownloads
    }

    let engine: DownloadEngineProtocol
    let vpnDetector: any VPNDetecting
    private let envProbe: EnvironmentProbing
    let log: LogWriter
    let persistence: (any QueuePersisting)?
    let revealSink: RevealSink
    let openURLSink: OpenURLSink
    let engineJobLogDir: URL
    private let suppression: SuppressionStore
    private var confirmationContinuation: CheckedContinuation<Bool, Never>?
    private var consumerTask: Task<Void, Never>?

    init(
        engine: DownloadEngineProtocol,
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
        columnConfig: ColumnConfig = .default,
        vpnDetector: any VPNDetecting = InterfaceVPNDetector()
    ) {
        self.engine = engine
        self.vpnDetector = vpnDetector
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
        if !needsOnboarding {
            await engine.ensureShield()
        }
        startConsumerIfNeeded()
    }

    func performLaunchSetup() async {
        guard !debugFlags.resetState, let persistence else { return }
        let active = persistence.loadQueue()
        let history = persistence.loadHistory()
        await engine.restore(active: active, history: history)
        let snapshot = await engine.currentSnapshot()
        rowStore.resync(
            snapshot,
            maxAutoRetries: prefs.maxAutoRetries,
            vpnActive: vpnDetector.isVPNActive
        )
        applySnapshot(snapshot)
        loadPlaylistGroups(for: snapshot)
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
        await engine.ensureShield()
        await refreshOnboardingState()
    }

    func restartShield() async {
        await engine.restartShield()
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

    func resetCircuit(host: RateHost) async {
        await engine.resetCircuit(host)
    }

    func resetAllCircuits() async {
        await engine.resetAllCircuits()
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
}

extension AppModel {
    func resolvePasted(_ url: String) async {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isProbing = true
        probeError = nil

        switch PlaylistLink.classify(trimmed) {
        case .youtubeUnsupported:
            await resolveUnsupportedPlaylistLink(trimmed)
        case .youtubePlaylist:
            await resolvePlaylist(trimmed)
        case .singleVideo:
            await resolveVideo(trimmed)
        }
    }

    func clearResolved() {
        resolved = nil
        probeError = nil
        isPlaylistPickerPresented = false
    }

    func grab(overrides: RunwayOverrides = RunwayOverrides()) async {
        guard let resolved else { return }
        guard case let .video(meta) = resolved else {
            isPlaylistPickerPresented = true
            return
        }
        let request = RequestBuilder.build(from: meta, prefs: prefs, overrides: overrides)
        rememberLastSelection(request, overrides: overrides)
        await submitGrab(request, metadata: meta)
    }

    func addPlaylistSelection(
        model picker: PlaylistPickerModel,
        overrides: RunwayOverrides
    ) async {
        let entries = picker.dump.entries.filter { picker.checked.contains($0.playlistIndex) }
        guard !entries.isEmpty else { return }

        let existingGroupID = existingPlaylistGroupID(for: picker.dump)
        let isNewGroup = existingGroupID == nil
        let groupID = existingGroupID ?? UUID()
        let items = entries.map {
            playlistSubmitItem(
                entry: $0,
                picker: picker,
                overrides: overrides,
                groupID: groupID
            )
        }
        if let first = items.first {
            rememberLastSelection(first.request, overrides: overrides)
        }
        let ids = await engine.submitPlaylistItems(items)
        guard !ids.isEmpty else { return }
        if isNewGroup {
            registerPlaylistGroup(id: groupID, for: picker.dump)
        }
        if let firstID = ids.first {
            lastSubmittedJobID = firstID
            scrollToRowID = firstID
        }
    }

    private func rememberLastSelection(
        _ request: DownloadRequest,
        overrides: RunwayOverrides
    ) {
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
        switch request.audioLanguage {
        case .original:
            prefs.lastAudioLanguage = .original
        case let .code(code):
            prefs.lastAudioLanguage = .code(code)
        case .unspecified:
            break
        }
    }

    private func submitGrab(_ request: DownloadRequest, metadata: MediaMetadata) async {
        let result = await engine.submit(request, force: false, prefetchedMetadata: metadata)
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
                let forced = await engine.submit(request, force: true, prefetchedMetadata: metadata)
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

    private func startConsumerIfNeeded() {
        guard consumerTask == nil else { return }
        consumerTask = Task { [weak self] in
            await self?.runConsumer()
        }
    }

    private func runConsumer() async {
        while !Task.isCancelled {
            for await event in engine.events {
                rowStore.apply(
                    event,
                    maxAutoRetries: prefs.maxAutoRetries,
                    vpnActive: vpnDetector.isVPNActive
                )
                if case let .snapshot(snapshot) = event {
                    rowStore.applyGroups(playlistGroups)
                    hostRateSummary = snapshot.hostRateSummary
                    healthController.update(snapshot: snapshot, now: .now)
                    recomputeBanner(snapshot)
                    applySnapshot(snapshot)
                }
            }
            await log.log(.consumerStreamEnded)
            try? await Task.sleep(for: .seconds(1))
            let snapshot = await engine.currentSnapshot()
            await rowStore.resync(
                snapshot,
                maxAutoRetries: prefs.maxAutoRetries,
                vpnActive: vpnDetector.isVPNActive
            )
            await rowStore.applyGroups(playlistGroups)
        }
    }

    private func applySnapshot(_ snapshot: QueueSnapshot) {
        if snapshot.queueHalt == .depMissing {
            needsOnboarding = true
        }
    }
}
