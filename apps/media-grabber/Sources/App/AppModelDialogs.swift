import Foundation
import GrabberKit

enum AppModelDialogs {
    static let unsupportedPlaylistLink = "This link isn't a video or a playlist."

    static func duplicateConfirmation(wasCompleted: Bool) -> ConfirmationRequest {
        if wasCompleted {
            ConfirmationRequest(
                title: "Download again?",
                message: "You've already downloaded this.",
                confirmTitle: "Download Again",
                cancelTitle: "Cancel"
            )
        } else {
            ConfirmationRequest(
                title: "Already in your queue",
                message: "This link is already waiting to download.",
                confirmTitle: "Download Again",
                cancelTitle: "Cancel"
            )
        }
    }

    static func revealMissingConfirmation() -> ConfirmationRequest {
        ConfirmationRequest(
            title: "File moved",
            message: "The file is no longer at that location.",
            confirmTitle: "OK",
            cancelTitle: nil
        )
    }

    static func showLogMissingNotice() -> ConfirmationRequest {
        ConfirmationRequest(
            title: "Log unavailable",
            message: "The log for this download is no longer available.",
            confirmTitle: "OK",
            cancelTitle: nil
        )
    }

    static func playlistCancelAllConfirmation() -> ConfirmationRequest {
        ConfirmationRequest(
            title: "Cancel this playlist?",
            message: "Videos still waiting or downloading will stop. Files already saved stay.",
            confirmTitle: "Cancel All",
            cancelTitle: "Keep",
            isDestructive: true,
            suppressionKey: "playlist-cancel-all"
        )
    }

    static func probeErrorMessage(for error: MetadataError, vpnActive: Bool = false) -> String {
        switch error {
        case .badURL: "That doesn't look like a valid link."
        case .unsupported: "That site isn't supported."
        case .unavailable: "This video isn't available."
        case .network: "No internet connection."
        case .ytDlpMissing, .launchFailed: "yt-dlp is missing — reopen setup."
        case .malformedOutput: "Couldn't read the video details."
        case .botCheck:
            BotCheckCopy.sentence(vpnActive: vpnActive)
        case .hostBlocked:
            "This site is cooling down. Try again in a moment."
        case .unknown: "Couldn't read the video details."
        }
    }
}
