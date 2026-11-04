import AppKit
import Foundation
import GrabberKit
import Observation

@MainActor
@Observable
final class AppModel {
    enum Page: Equatable {
        case home
        case preferences(PreferencesPane = .downloads)
        case about(AboutTab = .about)
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
    private(set) var latestEnvironmentReport: EnvironmentReport?
    private(set) var lastSubmittedJobID: UUID?
    var homeFieldText = ""
    var filledProbeURL: String?

    var resolved: ResolvedLink?
    var probeError: String?
    // Identifies the newest link check; a slower, older check must not overwrite the newer one's result.
    var probeSerial = 0
    var probingURL: String?
    var passcodeNeeded: PasscodePrompt?
    var isPasscodeSheetShown = false
    var isProbing = false
    var playlistGroups: [PersistedPlaylistGroup] = []
    var isPlaylistPickerPresented = false
    var pendingConfirmation: ConfirmationRequest?
    var scrollToRowID: UUID?
    var bannerContent: BannerContent?
    let debugFlags: DebugFlags
    let defaults: UserDefaults

    @ObservationIgnored weak var incomingLinkController: IncomingLinkController?

    var columnConfig: ColumnConfig = .default {
        didSet {
            guard columnConfig != oldValue else { return }
            rowStore.setColumnConfig(columnConfig)
            persistence?.saveColumns(columnConfig)
        }
    }

    let rowStore = RowStore()
    var youtubeCheckNudgeDismissedStorage = false
    let toastCenter = ToastCenter()
    let shieldSetup: ShieldSetupController
    let notificationRouter: any NotificationRouting
    var isAppActive: @Sendable () -> Bool = { NSApp?.isActive ?? true }
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

    var isHomeBusy: Bool {
        !homeFieldText.isEmpty || isProbing || isPlaylistPickerPresented
    }

    let engine: DownloadEngineProtocol
    let vpnDetector: any VPNDetecting
    let envProbe: EnvironmentProbing
    let ytDlpUpdater: YtDlpUpdating
    let log: LogWriter
    let persistence: (any QueuePersisting)?
    let revealSink: RevealSink
    let openURLSink: OpenURLSink
    let appUpdateChecker: AppUpdateChecker
    let appVersion: String
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
        ytDlpUpdater: YtDlpUpdating = YtDlpUpdater(),
        debugFlags: DebugFlags = DebugFlags(),
        defaults: UserDefaults = .standard,
        notificationRouter: any NotificationRouting = NotificationRouter(),
        revealSink: RevealSink = WorkspaceRevealSink(),
        openURLSink: OpenURLSink = WorkspaceOpenURLSink(),
        appUpdateChecker: AppUpdateChecker = AppUpdateChecker(),
        shieldInstaller: ShieldInstaller = ShieldInstaller(),
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
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
        self.ytDlpUpdater = ytDlpUpdater
        self.debugFlags = debugFlags
        self.defaults = defaults
        self.notificationRouter = notificationRouter
        self.revealSink = revealSink
        self.openURLSink = openURLSink
        self.appUpdateChecker = appUpdateChecker
        shieldSetup = ShieldSetupController(
            installer: shieldInstaller,
            restart: { await engine.restartShield() },
            openURL: openURLSink
        )
        self.appVersion = appVersion
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
        shieldSetup.onInstalled = { [weak self] in await self?.reprobeCurrentLink() }
        youtubeCheckNudgeDismissedStorage = defaults.bool(forKey: "mg.youtubeCheckNudgeDismissed")
    }

    private var didRunLaunchSetup = false

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
        await engine.loadPlaylistGroupsFromPersistence()
        let withGroups = await engine.currentSnapshot()
        loadPlaylistGroups(for: withGroups)
    }

    func refreshOnboardingState() async {
        if debugFlags.forceOnboarding {
            needsOnboarding = true
            return
        }
        let report = await envProbe.probe()
        latestEnvironmentReport = report
        needsOnboarding = !report.isReadyForDownloads || !hasCompletedOnboarding
    }

    func onboardingFinished() async {
        await engine.revalidate()
        await engine.ensureShield()
        await refreshOnboardingState()
    }

    // Setter lives beside the private(set) property; AppModelDiagnostics.swift calls it to refresh after a restart.
    func setLatestEnvironmentReport(_ report: EnvironmentReport) {
        latestEnvironmentReport = report
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

    func setPendingCookieRetry(_ id: UUID?) {
        pendingCookieRetryJobID = id
    }

    // Setter lives beside the private(set) property; AppModelQueueFlow.swift calls it from the grab/resolve flow.
    func setLastSubmittedJobID(_ id: UUID?) {
        lastSubmittedJobID = id
    }

    func startConsumerIfNeeded() {
        guard consumerTask == nil else { return }
        consumerTask = Task { [weak self] in
            await self?.runConsumer()
        }
    }

    #if DEBUG
        func startConsumerForTesting() {
            startConsumerIfNeeded()
        }
    #endif

    private func runConsumer() async {
        while !Task.isCancelled {
            for await event in engine.events {
                let previousStates = Dictionary(
                    uniqueKeysWithValues: rowStore.rows.map { ($0.id, $0.snapshot.state) }
                )
                rowStore.apply(
                    event,
                    maxAutoRetries: prefs.maxAutoRetries,
                    vpnActive: vpnDetector.isVPNActive
                )
                if case let .snapshot(snapshot) = event {
                    handleJobTransitions(snapshot, previousStates: previousStates)
                    syncPlaylistGroups(from: snapshot)
                    hostRateSummary = snapshot.hostRateSummary
                    healthController.update(snapshot: snapshot, now: .now, environmentReport: latestEnvironmentReport)
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
            syncPlaylistGroups(from: snapshot)
        }
    }

    func applySnapshot(_ snapshot: QueueSnapshot) {
        if snapshot.queueHalt == .depMissing {
            needsOnboarding = true
        }
    }
}

extension AppModel {
    func onAppear() async {
        guard !didRunLaunchSetup else { return }
        didRunLaunchSetup = true
        await log.log(.appLaunched)
        await performLaunchSetup()
        await refreshOnboardingState()
        if !needsOnboarding {
            await engine.ensureShield()
        }
        startConsumerIfNeeded()
        Task { await checkForAppUpdateOnLaunch() }
    }
}
