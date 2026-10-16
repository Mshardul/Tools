import SwiftUI

struct BannerContent {
    let text: String
    let buttonTitle: String?
    let action: (@Sendable () async -> Void)?
}

struct BannerHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct WarningBanner: View {
    let content: BannerContent?

    @Environment(\.theme) private var theme

    var body: some View {
        if let content {
            HStack(spacing: Spacing.s3) {
                Text(content.text)
                    .font(theme.bodyFont(13, .regular))
                    .foregroundStyle(theme.palette.onAccent)
                Spacer(minLength: Spacing.s3)
                if let title = content.buttonTitle, let action = content.action {
                    Button(title) {
                        Task { await action() }
                    }
                    .buttonStyle(.plain)
                    .font(theme.bodyFont(12, .semibold))
                    .foregroundStyle(theme.palette.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s3)
            .background(
                LinearGradient(
                    colors: [theme.palette.bannerFillStart, theme.palette.bannerFillEnd],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: theme.cardRadius)
            )
            .shadow(color: .black.opacity(0.45), radius: 17, y: 10)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: BannerHeightKey.self, value: proxy.size.height)
            })
            .padding(.horizontal, Spacing.s4)
            .padding(.bottom, Spacing.s4)
        }
    }
}
