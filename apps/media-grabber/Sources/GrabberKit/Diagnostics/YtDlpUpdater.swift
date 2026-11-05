import CryptoKit
import Foundation

public enum YtDlpUpdateResult: Sendable, Equatable {
    case success(newVersion: String)
    case failure(reason: String)
}

public protocol YtDlpUpdating: Sendable {
    func reinstallToMinimum() async -> YtDlpUpdateResult
}

public struct YtDlpFetchError: Error, Equatable, Sendable {
    public let message: String
}

public struct YtDlpBinary: Sendable, Equatable {
    public let version: String
    public let bytes: Data
    public let sha256Hex: String

    public init(version: String, bytes: Data, sha256Hex: String) {
        self.version = version
        self.bytes = bytes
        self.sha256Hex = sha256Hex
    }
}

public protocol YtDlpReleaseFetching: Sendable {
    func latest() async -> Result<YtDlpBinary, YtDlpFetchError>
}

public struct YtDlpUpdater: YtDlpUpdating {
    private let fetcher: YtDlpReleaseFetching
    private let binDirectory: URL
    private let minimumVersion: String
    private let canary: @Sendable (URL) async -> Bool

    public init(
        fetcher: YtDlpReleaseFetching,
        binDirectory: URL,
        minimumVersion: String = EngineTuning.default.minimumYtDlpVersion,
        canary: @escaping @Sendable (URL) async -> Bool = { url in
            if case .success = await CanaryProbe.run(ytDlpPath: url, runner: ProcessRunner()) {
                return true
            }
            return false
        }
    ) {
        self.fetcher = fetcher
        self.binDirectory = binDirectory
        self.minimumVersion = minimumVersion
        self.canary = canary
    }

    public init() {
        let bin = ManagedTools.live().supportRoot.appendingPathComponent("bin")
        self.init(fetcher: GitHubYtDlpReleaseFetcher(), binDirectory: bin)
    }

    public func reinstallToMinimum() async -> YtDlpUpdateResult {
        let fetched: YtDlpBinary
        switch await fetcher.latest() {
        case let .success(binary):
            fetched = binary
        case let .failure(error):
            return .failure(reason: error.message)
        }
        guard let downloaded = DottedVersion(parsing: fetched.version),
              let minimum = DottedVersion(parsing: minimumVersion),
              downloaded >= minimum
        else {
            return .failure(reason: "The newest downloader is older than this app allows.")
        }
        let digest = SHA256.hash(data: fetched.bytes).map { String(format: "%02x", $0) }.joined()
        guard digest == fetched.sha256Hex.lowercased() else {
            return .failure(reason: "The downloaded file didn't match its checksum.")
        }
        let fileManager = FileManager.default
        let incoming = binDirectory.appendingPathComponent("yt-dlp.incoming")
        let destination = binDirectory.appendingPathComponent("yt-dlp")
        do {
            try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)
            try fetched.bytes.write(to: incoming, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: incoming.path)
        } catch {
            try? fileManager.removeItem(at: incoming)
            return .failure(reason: "The download didn't finish.")
        }
        guard await canary(incoming) else {
            try? fileManager.removeItem(at: incoming)
            return .failure(reason: "The new downloader didn't pass a check, so the included copy stays in use.")
        }
        do {
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: incoming)
            } else {
                try fileManager.moveItem(at: incoming, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: incoming)
            return .failure(reason: "The download didn't finish.")
        }
        return .success(newVersion: fetched.version)
    }
}

public struct GitHubYtDlpReleaseFetcher: YtDlpReleaseFetching {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func latest() async -> Result<YtDlpBinary, YtDlpFetchError> {
        do {
            let tag = try await releaseTag()
            let binaryURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/download/\(tag)/yt-dlp_macos")!
            let sumsURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/download/\(tag)/SHA2-256SUMS")!
            let (bytes, _) = try await session.data(from: binaryURL)
            let (sumsData, _) = try await session.data(from: sumsURL)
            let sums = String(data: sumsData, encoding: .utf8) ?? ""
            guard let checksum = Self.checksum(in: sums, filename: "yt-dlp_macos") else {
                return .failure(YtDlpFetchError(message: "The download didn't finish."))
            }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            return .success(YtDlpBinary(version: version, bytes: bytes, sha256Hex: checksum))
        } catch {
            return .failure(YtDlpFetchError(message: "The download didn't finish."))
        }
    }

    private func releaseTag() async throws -> String {
        let url = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await session.data(for: request)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let tag = object?["tag_name"] as? String, !tag.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return tag
    }

    static func checksum(in sums: String, filename: String) -> String? {
        for line in sums.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "*" || $0 == "\t" })
            guard parts.count >= 2, parts.last == Substring(filename) else { continue }
            return String(parts[0]).lowercased()
        }
        return nil
    }
}
