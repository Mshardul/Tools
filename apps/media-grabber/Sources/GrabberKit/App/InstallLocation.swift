import Foundation

public enum InstallMoveError: Error, Equatable {
    case destinationExists
}

public enum InstallLocation {
    public static let updateBlockedMessage =
        "Move MediaGrabber into Applications before it can update itself."
    public static let moveTitle = "Move MediaGrabber to Applications?"
    public static let moveMessage =
        "It can't update itself from this location. Your downloads stay where they are."
    public static let alreadyThereMessage =
        "A copy is already in Applications. Quit this one and open that copy."
    public static let moveFailedMessage = "MediaGrabber couldn't move itself. Drag it into Applications."

    public static func canReplaceItself(bundleURL: URL, home: URL) -> Bool {
        let path = resolvedPath(bundleURL)
        return applicationsRoots(home: home).contains { root in
            path == root || path.hasPrefix(root + "/")
        }
    }

    public static func destination(
        bundleURL: URL,
        home: URL,
        systemApplicationsWritable: Bool
    ) -> URL {
        let root = systemApplicationsWritable
            ? URL(fileURLWithPath: "/Applications", isDirectory: true)
            : home.appendingPathComponent("Applications", isDirectory: true)
        return root.appendingPathComponent(bundleURL.lastPathComponent, isDirectory: true)
    }

    public static func move(
        bundleURL: URL,
        to destination: URL,
        fileManager: FileManager = .default
    ) throws {
        let parent = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        if fileManager.fileExists(atPath: destination.path) {
            throw InstallMoveError.destinationExists
        }
        try fileManager.moveItem(at: bundleURL, to: destination)
    }

    private static func applicationsRoots(home: URL) -> [String] {
        [
            "/Applications",
            resolvedPath(home.appendingPathComponent("Applications", isDirectory: true))
        ]
    }

    private static func resolvedPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
