import GrabberKit
@testable import MediaGrabber
import XCTest

@MainActor
final class UserFacingJargonTests: XCTestCase {
    func testNamedSurfacesUsePlainWords() {
        let on = shieldLabel(.running(port: 4416))
        let offline = shieldLabel(.down)
        let missing = shieldLabel(.missing)
        let sentences = [
            on,
            offline,
            missing,
            HealthChipAccessibility.refreshLabel(id: "shield"),
            OnboardingView.youtubeCheckTitle,
            AboutView.downloaderTitle,
            AboutView.mediaToolsTitle,
            BotCheckCopy.sentence(vpnActive: false, shieldStatus: .down, isYouTube: true, advice: .suggest),
            BotCheckCopy.sentence(vpnActive: false, shieldStatus: .missing, isYouTube: true, advice: .suggest),
            AppModelDialogs.probeErrorMessage(for: .ytDlpMissing)
        ]
        XCTAssertEqual(on, "YouTube check · on")
        XCTAssertEqual(offline, "YouTube check · offline")
        XCTAssertEqual(missing, "YouTube check · not set up")
        XCTAssertEqual(sentences[3], "Restart YouTube check")
        XCTAssertEqual(OnboardingView.youtubeCheckTitle, "YouTube check")
        XCTAssertEqual(AboutView.downloaderTitle, "Downloader")
        XCTAssertEqual(AboutView.mediaToolsTitle, "Media tools")
        XCTAssertEqual(
            AppModelDialogs.probeErrorMessage(for: .ytDlpMissing),
            "The downloader isn't installed. Open setup."
        )
        for sentence in sentences {
            let lower = sentence.lowercased()
            XCTAssertFalse(lower.contains("yt-dlp"), sentence)
            XCTAssertFalse(lower.contains("pipx"), sentence)
            XCTAssertFalse(lower.contains("ffmpeg"), sentence)
            XCTAssertFalse(lower.contains("shield"), sentence)
        }
    }

    private func shieldLabel(_ status: ShieldStatus) -> String {
        let controller = HealthController()
        controller.update(
            snapshot: QueueSnapshot(
                jobs: [],
                revision: 1,
                queueHalt: nil,
                generatedAt: .now,
                hostRateSummary: [:],
                isOnline: true,
                shieldStatus: status
            ),
            now: .now,
            environmentReport: nil
        )
        return controller.chips[0].label
    }
}
