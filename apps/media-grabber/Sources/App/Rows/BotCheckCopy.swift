import Foundation
import GrabberKit

enum BotCheckCopy {
    // The shield only helps with YouTube, so it is never blamed for another site's refusal.
    static func sentence(vpnActive: Bool, shieldStatus: ShieldStatus, isYouTube: Bool) -> String {
        let site = isYouTube ? "YouTube" : "This site"
        if isYouTube {
            switch shieldStatus {
            case .down:
                return "YouTube didn't accept this request because the bot-check shield stopped working."
            case .missing:
                return "YouTube didn't accept this request. "
                    + "The bot-check shield that helps with this isn't set up on this Mac."
            case .running:
                break
            }
        }
        return vpnActive
            ? "\(site) didn't accept this request. Try turning off your VPN, or sign in with your browser in "
            + "Preferences."
            : "\(site) didn't accept this request. Try again, or sign in with your browser in Preferences."
    }
}
