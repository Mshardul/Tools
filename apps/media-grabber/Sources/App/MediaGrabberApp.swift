import GrabberKit
import SwiftUI

@main
struct MediaGrabberApp: App {
    @State private var appModel: AppModel
    @State private var installer: OnboardingInstaller

    init() {
        let prefs = Preferences()
        let installer = OnboardingInstaller()
        let ytDlpURL = Self.resolveYtDlp()
        let log = LogWriter()
        let persistence = Persistence(log: log)
        let engine = DownloadEngine(
            dependencies: .live(ytDlpURL: ytDlpURL, log: log, persistence: persistence),
            preferences: prefs
        )
        let probe = MetadataProbe(ytDlpURL: ytDlpURL)
        let forceOnboarding = CommandLine.arguments.contains("-MGForceOnboarding")

        _installer = State(initialValue: installer)
        _appModel = State(initialValue: AppModel(
            engine: engine,
            probe: probe,
            installer: installer,
            prefs: prefs,
            log: log,
            forceOnboarding: forceOnboarding
        ))
    }

    var body: some Scene {
        WindowGroup {
            content
                .theme(ResolvedTheme(
                    skinKind: appModel.prefs.skin,
                    paletteKind: appModel.prefs.palette
                ))
                .environment(appModel)
                .background(WindowFrameAutosave(name: "MediaGrabberMain"))
                .task { await appModel.onAppear() }
        }
        .defaultSize(width: 980, height: 720)
        .windowResizability(.contentSize)
    }

    @ViewBuilder
    private var content: some View {
        if appModel.needsOnboarding {
            OnboardingView(installer: installer)
                .onChange(of: installer.canProceedToHome) { _, canProceed in
                    if canProceed {
                        Task { await appModel.refreshOnboardingState() }
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
