import SwiftUI

struct ShieldSetupSheet: View {
    @Bindable var controller: ShieldSetupController
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Text("Set up the bot-check shield")
                .font(theme.displayFont(20, .semibold))
                .foregroundStyle(theme.palette.headline)
            Text(Self.explanation(for: controller.state))
                .font(theme.bodyFont(13, .regular))
                .foregroundStyle(theme.palette.text)
                .fixedSize(horizontal: false, vertical: true)
            if case let .failed(detail) = controller.state {
                DisclosureGroup("Details") {
                    Text(detail)
                        .font(theme.monoFont(11, .regular))
                        .foregroundStyle(theme.palette.dim)
                        .textSelection(.enabled)
                }
                .font(theme.bodyFont(12, .regular))
            }
            if controller.isWorking {
                ProgressView().controlSize(.small).tint(theme.palette.accent)
            }
            HStack(spacing: Spacing.s3) {
                Spacer()
                secondaryButton
                primaryButton
            }
        }
        .padding(Spacing.s6)
        .frame(width: 460)
        .background(theme.palette.ground)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch controller.state {
        case .idle:
            Button("Set up now") { Task { await controller.run() } }
                .keyboardShortcut(.defaultAction)
        case .working:
            Button("Setting up…") {}.disabled(true)
        case .done:
            Button("Done") { controller.dismiss() }.keyboardShortcut(.defaultAction)
        case .needsHomebrew:
            Button("Get Homebrew") { controller.openHomebrewSite() }.keyboardShortcut(.defaultAction)
        case .failed:
            Button("Try again") { Task { await controller.run() } }.keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var secondaryButton: some View {
        if controller.state != .done {
            Button(controller.isWorking ? "Close" : "Not now") { controller.dismiss() }
        }
    }

    static func explanation(for state: ShieldSetupController.State) -> String {
        switch state {
        case .idle:
            "YouTube sometimes asks apps to prove they aren't a robot. The bot-check shield is a small free helper "
                + "that handles this for you. Setting it up takes about a minute."
        case .working:
            "Setting up. This can take a minute."
        case .done:
            "All set. Try your download again."
        case .needsHomebrew:
            "Setting this up needs Homebrew, a free tool installer for Mac. Install Homebrew, then come back and "
                + "try again."
        case .failed:
            "Setup didn't finish. Check your internet connection and try again."
        }
    }
}
