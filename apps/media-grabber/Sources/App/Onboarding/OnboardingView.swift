import GrabberKit
import SwiftUI

#if canImport(AppKit)
    import AppKit
#endif

struct OnboardingView: View {
    @Bindable var installer: OnboardingInstaller
    let onContinue: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.palette.hair)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s5) {
                    intro
                    VStack(spacing: 0) {
                        ForEach(OnboardingStepID.allCases, id: \.self) { step in
                            row(step)
                            Divider().overlay(theme.palette.hair)
                        }
                    }
                    continueRow
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.vertical, Spacing.s7)
                .frame(maxWidth: .infinity)
            }
        }
        .background(theme.palette.ground.ignoresSafeArea())
        .task { await installer.check() }
    }

    private var header: some View {
        HStack(spacing: Spacing.s3) {
            MotifView(isActive: true, size: 20)
            Text("MediaGrabber")
                .font(theme.displayFont(17, .semibold))
                .foregroundStyle(theme.palette.text)
            Spacer()
        }
        .padding(.horizontal, Spacing.s5)
        .padding(.vertical, Spacing.s3)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text("FIRST RUN")
                .font(theme.monoFont(11, .medium))
                .foregroundStyle(theme.palette.accent)
            Text("Let\u{2019}s get you set up.")
                .font(theme.displayFont(30, .semibold))
                .foregroundStyle(theme.palette.headline)
            Text("MediaGrabber uses a few free tools to do the actual downloading. Anything already on your Mac is "
                + "checked off below.")
                .font(theme.bodyFont(14, .regular))
                .foregroundStyle(theme.palette.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var continueRow: some View {
        HStack(spacing: Spacing.s3) {
            primaryButton("Continue", enabled: installer.canProceedToHome, action: onContinue)
            if !installer.canProceedToHome {
                Text("Continue unlocks once the required tools are installed.")
                    .font(theme.bodyFont(12, .regular))
                    .foregroundStyle(theme.palette.faint)
            }
        }
    }

    @ViewBuilder
    private func row(_ step: OnboardingStepID) -> some View {
        let state = installer.steps[step] ?? .pending
        HStack(alignment: .top, spacing: Spacing.s4) {
            icon(for: state, index: OnboardingStepID.allCases.firstIndex(of: step) ?? 0)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(title(for: step))
                    .font(theme.bodyFont(15, .semibold))
                    .foregroundStyle(theme.palette.text)
                    .accessibilityLabel("\(title(for: step)), \(spokenState(state))")
                Text(summary(for: step, state: state))
                    .font(theme.bodyFont(13, .regular))
                    .foregroundStyle(theme.palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
                actions(for: step, state: state)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.s4)
    }

    @ViewBuilder
    private func icon(for state: OnboardingStepState, index: Int) -> some View {
        switch state {
        case .done, .skipped:
            Circle().fill(theme.palette.accent)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.palette.onAccent)
                )
        case .running:
            ProgressView().controlSize(.small).tint(theme.palette.accent)
        case .failed:
            Circle().stroke(theme.palette.danger, lineWidth: 1.5)
                .overlay(
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.palette.danger)
                )
        case .pending:
            Circle().stroke(theme.palette.stroke, lineWidth: 1.5)
                .overlay(
                    Text("\(index + 1)")
                        .font(theme.monoFont(12, .medium))
                        .foregroundStyle(theme.palette.dim)
                )
        }
    }

    @ViewBuilder
    private func actions(for step: OnboardingStepID, state: OnboardingStepState) -> some View {
        switch (step, state) {
        case (.homebrew, .failed):
            homebrewActions
        case (.downloaderTools, .pending):
            VStack(alignment: .leading, spacing: Spacing.s3) {
                commandBox("brew install yt-dlp ffmpeg")
                primaryButton("Install now", enabled: true) { Task { await installer.start() } }
            }
        case (.botCheckShield, .pending):
            primaryButton("Set up", enabled: installer.canProceedToHome) {
                Task { await installer.installShieldOnly() }
            }
        case (_, .failed):
            Button("Try again") { Task { await retry(step) } }
                .buttonStyle(.plain)
                .font(theme.bodyFont(12, .semibold))
                .foregroundStyle(theme.palette.accent)
        default:
            EmptyView()
        }
    }

    private func retry(_ step: OnboardingStepID) async {
        switch step {
        case .botCheckShield:
            await installer.installShieldOnly()
        case .testRun:
            await installer.check()
        default:
            await installer.start()
        }
    }

    private var homebrewActions: some View {
        HStack(spacing: Spacing.s2) {
            Button("Copy command") { copy(HomebrewInstallInfo.command) }
            Button("Open Terminal") { installer.openTerminalForHomebrew() }
            Button("Check again") { Task { await installer.recheck() } }
        }
    }

    private func commandBox(_ command: String) -> some View {
        HStack(spacing: Spacing.s3) {
            Text(command)
                .font(theme.monoFont(12, .regular))
                .foregroundStyle(theme.palette.text)
                .textSelection(.enabled)
            Button("Copy") { copy(command) }
                .controlSize(.small)
        }
        .padding(Spacing.s3)
        .background(theme.palette.panel, in: RoundedRectangle(cornerRadius: theme.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: theme.controlRadius)
                .stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth)
        )
    }

    private func primaryButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(theme.bodyFont(13, .semibold))
                .foregroundStyle(theme.palette.onAccent)
                .padding(.horizontal, Spacing.s5)
                .padding(.vertical, Spacing.s2)
                .background(
                    LinearGradient(
                        colors: [theme.palette.goFillStart, theme.palette.goFillEnd],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: theme.controlRadius)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .grayscale(enabled ? 0 : 1)
    }

    private func copy(_ text: String) {
        #if canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func spokenState(_ state: OnboardingStepState) -> String {
        switch state {
        case .done: "done"
        case .skipped: "already set up"
        case .running: "in progress"
        case .failed: "needs attention"
        case .pending: "not started"
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

    private func summary(for step: OnboardingStepID, state: OnboardingStepState) -> String {
        switch state {
        case .skipped:
            "Already installed."
        case .done:
            step == .testRun ? "Everything works." : "Installed."
        case let .running(text):
            text.isEmpty ? "Working on it\u{2026}" : text
        case let .failed(reason):
            failureSummary(for: step, reason: reason)
        case .pending:
            pendingSummary(for: step)
        }
    }

    private func failureSummary(for step: OnboardingStepID, reason: String) -> String {
        switch step {
        case .botCheckShield: reason
        case .downloaderTools: "Setup didn't finish. Check your internet connection and try again."
        case .testRun: "The check didn't pass."
        case .homebrew: pendingSummary(for: step)
        }
    }

    private func pendingSummary(for step: OnboardingStepID) -> String {
        switch step {
        case .homebrew: "A free tool installer for Mac. The other tools install through it."
        case .downloaderTools: "Does the actual downloading. Required."
        case .botCheckShield: "Helps YouTube downloads get through. Recommended, not required."
        case .testRun: "We'll check a known video to confirm everything works."
        }
    }
}
