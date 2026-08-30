import SwiftUI

struct BannerContent {
    let text: String
    let buttonTitle: String
    let action: @Sendable () async -> Void
}

struct WarningBanner: View {
    let content: BannerContent?

    @Environment(\.theme) private var theme

    var body: some View {
        if let content {
            HStack(spacing: Spacing.s3) {
                Text(content.text)
                    .font(theme.skin.bodyFont(13, .regular))
                    .foregroundStyle(theme.palette.onAccent)
                Spacer(minLength: Spacing.s3)
                Button(content.buttonTitle) {
                    Task { await content.action() }
                }
                .buttonStyle(.plain)
                .font(theme.skin.bodyFont(13, .semibold))
                .foregroundStyle(theme.palette.onAccent)
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s3)
            .background(
                LinearGradient(
                    colors: [theme.palette.bannerFillStart, theme.palette.bannerFillEnd],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: theme.skin.cardRadius)
            )
            .padding(.horizontal, Spacing.s4)
            .padding(.bottom, Spacing.s4)
        }
    }
}
