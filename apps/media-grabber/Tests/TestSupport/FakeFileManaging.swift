import Foundation
import GrabberKit

public struct FakeFileManaging: FileManaging {
    public var files: Set<String> = []
    public var readable: Set<String> = []
    public var dirs: [String: [URL]] = [:]
    public var contents: [String: String] = [:]

    public init() {}

    public func fileExists(atPath path: String) -> Bool {
        files.contains(path)
    }

    public func contentsOfDirectory(at url: URL) -> [URL] {
        dirs[url.path] ?? []
    }

    public func dataReadable(at url: URL) -> Bool {
        readable.contains(url.path)
    }

    public func fileContents(at url: URL) -> String? {
        contents[url.path]
    }
}
