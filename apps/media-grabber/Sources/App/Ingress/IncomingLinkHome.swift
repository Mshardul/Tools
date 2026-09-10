import Foundation
import GrabberKit

@MainActor
protocol IncomingLinkHome: AnyObject {
    var isHomeBusy: Bool { get }
    var detectClipboardLinks: Bool { get }
    func applyIncomingURL(_ url: URL) async
    func confirm(_ request: ConfirmationRequest) async -> Bool
}
