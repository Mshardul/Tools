import Foundation
import GrabberKit

enum AppModelDialogs {
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

    static func probeErrorMessage(for error: MetadataError) -> String {
        switch error {
        case .badURL: "That doesn't look like a valid link."
        case .unsupported: "That site isn't supported."
        case .unavailable: "This video isn't available."
        case .network: "No internet connection."
        case .ytDlpMissing, .launchFailed: "yt-dlp is missing — reopen setup."
        case .malformedOutput: "Couldn't read the video details."
        case let .unknown(raw): raw
        }
    }
}
