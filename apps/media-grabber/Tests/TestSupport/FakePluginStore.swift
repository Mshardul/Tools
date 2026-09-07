import Foundation
import GrabberKit

public final class FakePluginStore: PluginStoring, @unchecked Sendable {
    public var files: Set<String> = []
    public var listings: [String: [URL]] = [:]
    public var copies: [(from: URL, to: URL)] = []
    public var created: [URL] = []

    public init() {}

    public func fileExists(atPath path: String) -> Bool {
        files.contains(path)
    }

    public func copyItem(at source: URL, to destination: URL) throws {
        copies.append((from: source, to: destination))
        files.insert(destination.path)
    }

    public func createDirectory(at url: URL) throws {
        created.append(url)
        files.insert(url.path)
    }

    public func contentsOfDirectory(at url: URL) -> [URL] {
        listings[url.path] ?? []
    }
}
