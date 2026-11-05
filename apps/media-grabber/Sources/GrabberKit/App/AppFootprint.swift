import Foundation

public enum AppFootprint {
    public static let preferenceDomain = "app.mediagrabber.mac"

    public static func directories(in home: URL) -> [URL] {
        let library = home.appendingPathComponent("Library", isDirectory: true)
        return [
            library.appendingPathComponent("Application Support/MediaGrabber", isDirectory: true),
            library.appendingPathComponent("Logs/MediaGrabber", isDirectory: true),
            library.appendingPathComponent("Caches/\(preferenceDomain)", isDirectory: true),
            library.appendingPathComponent(
                "Saved Application State/\(preferenceDomain).savedState",
                isDirectory: true
            )
        ]
    }

    public static func preferenceFile(in home: URL) -> URL {
        home
            .appendingPathComponent("Library/Preferences", isDirectory: true)
            .appendingPathComponent("\(preferenceDomain).plist")
    }

    public static func remove(in home: URL, fileManager: FileManager = .default) throws {
        for url in directories(in: home) where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        let preferences = preferenceFile(in: home)
        if fileManager.fileExists(atPath: preferences.path) {
            try fileManager.removeItem(at: preferences)
        }
    }
}
