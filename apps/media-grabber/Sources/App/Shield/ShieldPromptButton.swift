import SwiftUI

struct ShieldPromptButton: View {
    let prompt: ShieldSetupController.ProbePrompt

    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme

    var body: some View {
        Button(prompt == .setUp ? "Set up the shield" : "Restart the shield") {
            switch prompt {
            case .setUp:
                appModel.shieldSetup.present()
            case .restart:
                Task {
                    await appModel.restartShield()
                    await appModel.reprobeCurrentLink()
                }
            }
        }
        .buttonStyle(.plain)
        .font(theme.bodyFont(12, .semibold))
        .foregroundStyle(theme.palette.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
