import Foundation

enum BundledYtDlpPlugins {
    private final class BundleAnchor {}

    // Keeps yt-dlp from writing __pycache__ into the signed app bundle when it loads the plugins.
    static let launchEnvironment = ["PYTHONDONTWRITEBYTECODE": "1"]

    static var directories: [URL] {
        guard let root = Bundle(for: BundleAnchor.self).resourceURL?.appendingPathComponent("YtDlpPlugins"),
              FileManager.default.fileExists(atPath: root.path)
        else {
            return []
        }
        return [root]
    }
}
