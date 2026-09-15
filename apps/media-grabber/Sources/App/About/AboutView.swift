import GrabberKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AboutViewModel {
    let currentAppVersion: String
    private(set) var environmentReport: EnvironmentReport
    private(set) var appUpdateStatus: AppUpdateStatus = .notChecked
    private(set) var isCheckingAppUpdate = false
    private(set) var isReinstallingYtDlp = false

    private let updateChecker: AppUpdateChecker
    private let ytDlpUpdater: YtDlpUpdating

    init(
        currentAppVersion: String,
        environmentReport: EnvironmentReport,
        updateChecker: AppUpdateChecker,
        ytDlpUpdater: YtDlpUpdating
    ) {
        self.currentAppVersion = currentAppVersion
        self.environmentReport = environmentReport
        self.updateChecker = updateChecker
        self.ytDlpUpdater = ytDlpUpdater
    }

    func checkForAppUpdate() async {
        isCheckingAppUpdate = true
        defer { isCheckingAppUpdate = false }
        appUpdateStatus = await updateChecker.checkForUpdate(currentVersion: currentAppVersion)
    }

    func reinstallYtDlp() async {
        isReinstallingYtDlp = true
        defer { isReinstallingYtDlp = false }
        _ = await ytDlpUpdater.reinstallToMinimum()
    }
}

enum AboutTab: String, CaseIterable, Hashable {
    case about
    case developer

    var title: String {
        switch self {
        case .about: "About"
        case .developer: "Developer"
        }
    }
}

struct AboutView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme

    let selectedTab: AboutTab
    @State private var model: AboutViewModel?

    var body: some View {
        ScrollView {
            tabBody
                .padding(Spacing.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if model == nil {
                model = makeModel()
            }
        }
    }

    @ViewBuilder
    private var tabBody: some View {
        if let model {
            switch selectedTab {
            case .about:
                AboutTabView(model: model)
            case .developer:
                DeveloperView()
            }
        }
    }

    private func makeModel() -> AboutViewModel {
        AboutViewModel(
            currentAppVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
            environmentReport: appModel.latestEnvironmentReport ?? .init(brew: nil, ytDlp: nil, ffmpeg: nil),
            updateChecker: AppUpdateChecker(),
            ytDlpUpdater: appModel.ytDlpUpdater
        )
    }
}

private struct AboutTabView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme
    @Bindable var model: AboutViewModel

    var body: some View {
        VStack(spacing: 0) {
            MotifView(isActive: false, size: 56)
                .padding(.bottom, Spacing.s3)
            Text("MediaGrabber")
                .font(theme.displayFont(20, .heavy))
                .foregroundStyle(theme.palette.headline)
            Text("Version \(model.currentAppVersion)")
                .font(theme.bodyFont(12, .regular))
                .foregroundStyle(theme.palette.dim)
                .padding(.top, 2)
                .padding(.bottom, Spacing.s4)
            Divider().overlay(theme.palette.hair)

            VStack(alignment: .leading, spacing: 0) {
                appRow
                ytDlpRow
                ffmpegRow
                diagnosticsRow
            }
            .padding(.top, Spacing.s2)
        }
        .frame(maxWidth: .infinity)
    }

    private var appRow: some View {
        aboutRow(
            title: "MediaGrabber",
            subtitle: appUpdateSubtitle,
            trailing: AnyView(appUpdateTrailing)
        )
    }

    private var appUpdateSubtitle: String? {
        switch model.appUpdateStatus {
        case .notChecked: "Not checked yet this session."
        case .upToDate, .checkFailed: nil
        case let .updateAvailable(version, _): "Version \(version) is available."
        }
    }

    @ViewBuilder
    private var appUpdateTrailing: some View {
        switch model.appUpdateStatus {
        case .notChecked:
            textButton("Check for updates") {
                Task { await model.checkForAppUpdate() }
            }
            .disabled(model.isCheckingAppUpdate)
        case .upToDate:
            EmptyView()
        case .checkFailed:
            Text("Check failed")
                .font(theme.monoFont(12, .regular))
                .foregroundStyle(theme.palette.danger)
        case let .updateAvailable(_, releaseURL):
            textButton("Update") {
                appModel.openURLSink.open(releaseURL)
            }
        }
    }

    private var ytDlpRow: some View {
        aboutRow(
            title: "Downloader (yt-dlp)",
            subtitle: nil,
            trailing: AnyView(ytDlpTrailing)
        )
    }

    @ViewBuilder
    private var ytDlpTrailing: some View {
        switch model.environmentReport.ytDlpDriftVerdict {
        case .current, nil:
            statusText(installedYtDlpText, verdict: .ok)
        case .unknown:
            statusText(installedYtDlpText, verdict: .neutral)
        case let .drift(installed, _):
            HStack(spacing: Spacing.s2) {
                statusText("\(installed) · update available", verdict: .warn)
                Button {
                    Task { await model.reinstallYtDlp() }
                } label: {
                    Label("Update", systemImage: "arrow.clockwise")
                        .font(theme.bodyFont(11, .semibold))
                        .foregroundStyle(theme.palette.warn)
                        .padding(.horizontal, Spacing.s2)
                        .padding(.vertical, 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: theme.pillRadius)
                                .stroke(theme.palette.warn, lineWidth: theme.hairlineWidth)
                        )
                }
                .buttonStyle(.plain)
                .disabled(model.isReinstallingYtDlp)
            }
        }
    }

    private var installedYtDlpText: String {
        guard let version = model.environmentReport.ytDlp?.version else { return "not found" }
        return version
    }

    private var ffmpegRow: some View {
        aboutRow(
            title: "ffmpeg",
            subtitle: nil,
            trailing: AnyView(
                statusText(
                    model.environmentReport.ffmpeg?.version ?? "not found",
                    verdict: model.environmentReport.ffmpeg == nil ? .bad : .ok
                )
            )
        )
    }

    private var diagnosticsRow: some View {
        aboutRow(
            title: "Diagnostics",
            subtitle: "Run a health check or copy a report for support.",
            trailing: AnyView(
                textButton("Open Diagnostics") {
                    appModel.page = .preferences(.diagnostics)
                }
            ),
            showsDivider: false
        )
    }

    private func aboutRow(
        title: String,
        subtitle: String?,
        trailing: AnyView,
        showsDivider: Bool = true
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(theme.monoFont(12, .regular))
                    .foregroundStyle(theme.palette.dim)
                if let subtitle {
                    Text(subtitle)
                        .font(theme.bodyFont(10.5, .regular))
                        .foregroundStyle(theme.palette.faint)
                }
            }
            Spacer()
            trailing
        }
        .padding(.vertical, Spacing.s2)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Divider().overlay(theme.palette.hair)
            }
        }
    }

    private func textButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(theme.displayFont(12, .semibold))
                .foregroundStyle(theme.palette.text)
                .padding(.horizontal, Spacing.s3)
                .padding(.vertical, Spacing.s2)
                .background(theme.palette.panel, in: RoundedRectangle(cornerRadius: theme.chipRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.chipRadius)
                        .stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth)
                )
        }
        .buttonStyle(.plain)
    }

    private func statusText(_ text: String, verdict: AboutRowVerdict) -> some View {
        Text(text)
            .font(theme.monoFont(12, .regular))
            .foregroundStyle(verdict.color(theme))
    }
}

private enum AboutRowVerdict {
    case ok
    case warn
    case bad
    case neutral

    func color(_ theme: Theme) -> Color {
        switch self {
        case .ok: theme.palette.accent
        case .warn: theme.palette.warn
        case .bad: theme.palette.danger
        case .neutral: theme.palette.text
        }
    }
}
