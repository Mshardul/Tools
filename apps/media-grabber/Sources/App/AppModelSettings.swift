import Foundation

extension AppModel {
    var detectClipboardLinks: Bool {
        prefs.detectClipboardLinks
    }

    var maxConcurrentDownloads: Int {
        debugFlags.concurrencyCapOverride ?? prefs.maxConcurrentDownloads
    }
}
