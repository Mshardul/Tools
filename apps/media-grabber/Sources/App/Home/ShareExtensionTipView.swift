import SwiftUI

struct ShareExtensionTipView: View {
    @AppStorage("mg.shareExtensionTipDismissed") private var dismissed = false
    @Environment(\.theme) private var theme
    let openURLSink: OpenURLSink

    var body: some View {
        if !dismissed {
            HStack(spacing: Spacing.s3) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.palette.faint)
                    .accessibilityHidden(true)
                Text("Grab links straight from Safari: turn on MediaGrabber in System Settings → Extensions.")
                    .font(theme.bodyFont(12, .regular))
                    .foregroundStyle(theme.palette.dim)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Spacing.s3)
                Button("Open Settings") { openSettingsPane() }
                    .buttonStyle(.plain)
                    .font(theme.bodyFont(12, .semibold))
                    .foregroundStyle(theme.palette.accent)
                Button {
                    dismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.palette.faint)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s2)
            .background(
                theme.palette.panel.opacity(0.6),
                in: RoundedRectangle(cornerRadius: theme.controlRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.controlRadius)
                    .stroke(theme.palette.hair, lineWidth: theme.hairlineWidth)
            )
        }
    }

    private func openSettingsPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            openURLSink.open(url)
        }
    }
}
