import GrabberKit
import SwiftUI

@main
struct MediaGrabberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appModel: AppModel
    @State private var installer: OnboardingInstaller

    init() {
        let debugFlags = DebugFlags.parse(CommandLine.arguments)
        let prefs = Preferences()
        let installer = OnboardingInstaller()
        let ytDlpURL = Self.resolveYtDlp()
        let log = LogWriter()
        let persistence = Persistence(
            log: log,
            debug: PersistenceDebug(resetState: debugFlags.resetState)
        )
        let engineFlags = EngineDebugFlags(concurrencyCapOverride: debugFlags
            .concurrencyCapOverride)
        let engine = DownloadEngine(
            dependencies: .live(
                ytDlpURL: ytDlpURL,
                debugFlags: engineFlags,
                log: log,
                persistence: persistence
            ),
            preferences: prefs
        )
        let probe = MetadataProbe(ytDlpURL: ytDlpURL)

        let columnConfig = debugFlags.resetState ? ColumnConfig
            .default : (persistence.loadColumns() ?? .default)
        let model = AppModel(
            engine: engine,
            probe: probe,
            installer: installer,
            prefs: prefs,
            log: log,
            debugFlags: debugFlags,
            persistence: persistence,
            columnConfig: columnConfig
        )

        _installer = State(initialValue: installer)
        _appModel = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            content
                .theme(Theme(
                    themeKind: appModel.prefs.theme,
                    paletteKind: appModel.prefs.palette
                ))
                .environment(appModel)
                .background(WindowFrameAutosave(name: "MediaGrabberMain"))
                .task {
                    appDelegate.quitCoordinator = appModel.quitCoordinator
                    await appModel.onAppear()
                }
        }
        .defaultSize(width: 980, height: 720)
        .windowResizability(.contentMinSize)
    }

    @ViewBuilder
    private var content: some View {
        if appModel.needsOnboarding {
            OnboardingView(installer: installer)
                .onChange(of: installer.canProceedToHome) { _, canProceed in
                    if canProceed {
                        Task { await appModel.onboardingFinished() }
                    }
                }
        } else {
            MainWindow()
        }
    }

    private static func resolveYtDlp() -> URL {
        let candidates = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "\(NSHomeDirectory())/.local/bin/yt-dlp"
        ]
        let found = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        return URL(fileURLWithPath: found ?? "/opt/homebrew/bin/yt-dlp")
    }
}
