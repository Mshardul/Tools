import Foundation

public protocol FileManaging: Sendable {
    func fileExists(atPath path: String) -> Bool
    func contentsOfDirectory(at url: URL) -> [URL]
    func dataReadable(at url: URL) -> Bool
    func fileContents(at url: URL) -> String?
}

public struct FoundationFileManager: FileManaging {
    public init() {}

    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func contentsOfDirectory(at url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    public func dataReadable(at url: URL) -> Bool {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }

    public func fileContents(at url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }
}
