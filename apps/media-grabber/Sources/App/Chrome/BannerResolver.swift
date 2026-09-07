import Foundation

enum BannerReason: Equatable {
    case depMissing
    case networkDown
    case circuitOpen
    case potProviderDown
}

private let bannerPriority: [BannerReason] = [
    .depMissing, .networkDown, .circuitOpen, .potProviderDown
]

func resolveBanner(_ active: Set<BannerReason>) -> BannerReason? {
    bannerPriority.first(where: active.contains)
}

func bannerCopy(
    for reason: BannerReason,
    circuitHosts: [String],
    onRetry: @escaping @Sendable () async -> Void
) -> BannerContent? {
    switch reason {
    case .depMissing:
        return nil
    case .networkDown:
        return BannerContent(
            text: "No internet connection — downloads paused. They'll resume automatically.",
            buttonTitle: nil,
            action: nil
        )
    case .circuitOpen:
        let subject = circuitHosts.count == 1
            ? "Downloads from \(circuitHosts[0])"
            : "\(circuitHosts.count) sites"
        return BannerContent(
            text: "\(subject) keep getting rate-limited. "
                + "Wait a while, add browser cookies in Preferences, or turn off a VPN.",
            buttonTitle: "Retry now",
            action: onRetry
        )
    case .potProviderDown:
        return BannerContent(
            text: "Bot-check protection is offline — some downloads may fail or be low-res.",
            buttonTitle: "Restart",
            action: onRetry
        )
    }
}
