import Foundation

extension AppModel: IncomingLinkHome {}

extension AppModel {
    func setClipboardDetection(_ enabled: Bool) async {
        await incomingLinkController?.setClipboardDetectionEnabled(enabled)
    }
}
