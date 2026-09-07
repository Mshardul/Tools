import Foundation

enum BotCheckCopy {
    static func sentence(vpnActive: Bool) -> String {
        if vpnActive {
            return "Couldn't verify you. Turn off your VPN, or add browser cookies in Preferences."
        }
        return "Couldn't verify you. Try again, or add browser cookies in Preferences."
    }
}
