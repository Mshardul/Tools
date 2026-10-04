import SwiftUI

struct ShareExtensionTipView: View {
    @AppStorage("mg.shareExtensionTipDismissed") private var dismissed = false
    @Environment(\.theme) private var theme
    let openURLSink: OpenURLSink

    var body: some View {
        if !dismissed {
            HStack(alignment: .top, spacing: Spacing.s3) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("Enable the Share Extension")
                        .font(theme.bodyFont(13, .semibold))
                        .foregroundStyle(theme.palette.text)
                    Text(
                        "Turn on MediaGrabber under System Settings → Extensions to grab links from Safari."
                    )
                    .font(theme.bodyFont(12, .regular))
                    .foregroundStyle(theme.palette.dim)
                }
                Spacer(minLength: Spacing.s3)
                VStack(spacing: Spacing.s2) {
                    Button("Open System Settings") {
                        openSettingsPane()
                    }
                    .buttonStyle(.plain)
                    .font(theme.bodyFont(12, .semibold))
                    .foregroundStyle(theme.palette.accent)
                    Button("Dismiss") {
                        dismissed = true
                    }
                    .buttonStyle(.plain)
                    .font(theme.bodyFont(12, .regular))
                    .foregroundStyle(theme.palette.dim)
                }
            }
            .padding(Spacing.s4)
            .background(theme.palette.panel, in: RoundedRectangle(cornerRadius: theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: theme.cardRadius)
                    .stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth)
            )
        }
    }

    private func openSettingsPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            openURLSink.open(url)
        }
    }
}
