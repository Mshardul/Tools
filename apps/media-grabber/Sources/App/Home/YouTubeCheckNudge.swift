import GrabberKit
import SwiftUI

enum YouTubeCheckNudge {
    static let message = "YouTube downloads work better with the YouTube check set up."
    static let button = "Set it up"

    static func isVisible(onboardingComplete: Bool, shield: ShieldStatus?, dismissed: Bool) -> Bool {
        guard let shield else { return false }
        return onboardingComplete && shield == .missing && !dismissed
    }
}

struct YouTubeCheckNudgeBanner: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme

    var body: some View {
        let visible = YouTubeCheckNudge.isVisible(
            onboardingComplete: appModel.hasCompletedOnboarding,
            shield: appModel.healthController.shieldStatus,
            dismissed: appModel.youtubeCheckNudgeDismissed
        )
        if visible {
            HStack(spacing: Spacing.s3) {
                Text(YouTubeCheckNudge.message)
                    .font(theme.bodyFont(13, .regular))
                    .foregroundStyle(theme.palette.text)
                Button(YouTubeCheckNudge.button) {
                    appModel.shieldSetup.present()
                }
                Button("Dismiss") {
                    appModel.youtubeCheckNudgeDismissed = true
                }
            }
            .padding(.horizontal, Spacing.s6)
            .padding(.top, Spacing.s3)
        }
    }
}
