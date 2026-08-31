import GrabberKit
import SwiftUI

struct OnboardingView: View {
    @Bindable var installer: OnboardingInstaller
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.palette.ground.ignoresSafeArea()
            VStack(spacing: Spacing.s5) {
                header
                Text("Let's get you set up")
                    .font(theme.displayFont(26, .semibold))
                    .foregroundStyle(theme.palette.headline)
                VStack(spacing: Spacing.s3) {
                    ForEach(OnboardingStepID.allCases, id: \.self, content: row)
                }
            }
            .frame(maxWidth: 520)
            .padding(Spacing.s7)
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.s2) {
            MotifView(isActive: true, size: 20)
            Text("MediaGrabber")
                .font(theme.displayFont(18, .semibold))
                .foregroundStyle(theme.palette.text)
        }
    }

    @ViewBuilder
    private func row(_ step: OnboardingStepID) -> some View {
        let state = installer.steps[step] ?? .pending
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                icon(for: state, index: OnboardingStepID.allCases.firstIndex(of: step) ?? 0)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(for: step))
                        .font(theme.bodyFont(14, .medium))
                        .foregroundStyle(theme.palette.text)
                    Text(subtitle(for: step))
                        .font(theme.bodyFont(12, .regular))
                        .foregroundStyle(theme.palette.dim)
                    detail(for: step, state: state)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(Spacing.s3)
        .background(theme.palette.panel, in: RoundedRectangle(cornerRadius: theme.cardRadius))
    }

    @ViewBuilder
    private func icon(for state: OnboardingStepState, index: Int) -> some View {
        switch state {
        case .done, .skipped:
            Image(systemName: "checkmark")
                .foregroundStyle(theme.palette.accent)
        case .running:
            ProgressView()
                .controlSize(.small)
                .tint(theme.palette.accent)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.palette.danger)
        case .pending:
            Text("\(index + 1)")
                .font(theme.monoFont(12, .medium))
                .foregroundStyle(theme.palette.faint)
        }
    }

    @ViewBuilder
    private func detail(for step: OnboardingStepID, state: OnboardingStepState) -> some View {
        switch state {
        case let .running(text) where !text.isEmpty:
            Text(text)
                .font(theme.monoFont(11, .regular))
                .foregroundStyle(theme.palette.dim)
                .lineLimit(1)
                .truncationMode(.middle)
        case let .failed(reason) where step == .homebrew:
            homebrewFailure(reason: reason)
        case let .failed(reason):
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(reason)
                    .font(theme.monoFont(11, .regular))
                    .foregroundStyle(theme.palette.danger)
                Button("Retry") { Task { await installer.start() } }
            }
        default:
            EmptyView()
        }
    }

    private func homebrewFailure(reason: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(reason)
                .font(theme.monoFont(11, .regular))
                .foregroundStyle(theme.palette.text)
                .textSelection(.enabled)
                .padding(Spacing.s2)
                .background(
                    theme.palette.panelHi,
                    in: RoundedRectangle(cornerRadius: theme.chipRadius)
                )
            HStack(spacing: Spacing.s2) {
                Button("Copy") {
                    #if canImport(AppKit)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            HomebrewInstallInfo.command,
                            forType: .string
                        )
                    #endif
                }
                .accessibilityLabel("Copy Homebrew install command")
                Button("Open in Terminal") { installer.openTerminalForHomebrew() }
                Button("Re-check") { Task { await installer.recheck() } }
            }
        }
    }

    private func title(for step: OnboardingStepID) -> String {
        switch step {
        case .homebrew: "Homebrew"
        case .downloaderTools: "Downloader + media tools"
        case .botCheckShield: "Bot-check shield"
        case .testRun: "Test run"
        }
    }

    private func subtitle(for step: OnboardingStepID) -> String {
        switch step {
        case .homebrew: "The package manager the other tools install through."
        case .downloaderTools: "yt-dlp and ffmpeg — required to download."
        case .botCheckShield: "Helps with sites that challenge automated access. Optional."
        case .testRun: "A quick check that everything works."
        }
    }
}
