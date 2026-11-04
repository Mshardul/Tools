import Foundation
import GrabberKit

enum BotCheckCopy {
    // The shield only helps with YouTube, so it is never blamed for another site's refusal.
    static func sentence(
        vpnActive: Bool,
        shieldStatus: ShieldStatus,
        isYouTube: Bool,
        advice: SignInAdvice
    ) -> String {
        if isYouTube {
            switch shieldStatus {
            case .down:
                return "YouTube didn't accept this request because the YouTube check stopped working."
            case .missing:
                return "YouTube didn't accept this request. The YouTube check isn't set up on this Mac."
            case .running:
                break
            }
        }
        let site = isYouTube ? "YouTube" : "This site"
        let vpnHint = "Try turning off your VPN"
        switch advice {
        case .suggest:
            let first = vpnActive ? vpnHint : "Try again"
            return "\(site) didn't accept this request. \(first), or sign in with your browser in Preferences."
        case .checkBrowser:
            let first = vpnActive ? vpnHint : "Try again"
            return "\(site) didn't accept this request. \(first), or check that your browser is signed in to \(site)."
        case .none:
            return vpnActive
                ? "\(site) didn't accept this request. Try turning off your VPN."
                : "\(site) didn't accept this request. Try again later, or turn off your VPN."
        }
    }
}
