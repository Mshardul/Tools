import Foundation

public protocol PluginStoring: Sendable {
    func fileExists(atPath: String) -> Bool
    func copyItem(at: URL, to: URL) throws
    func createDirectory(at: URL) throws
    func contentsOfDirectory(at: URL) -> [URL]
}

public struct FoundationPluginStore: PluginStoring {
    public init() {}

    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func copyItem(at source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func contentsOfDirectory(at url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
    }
}
