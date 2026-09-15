import Foundation
import GrabberKit

struct GitHubRelease: Sendable, Equatable {
    let tagName: String
    let htmlURL: URL
}

protocol GitHubReleaseChecking: Sendable {
    func latestRelease(owner: String, repo: String) async throws -> GitHubRelease
}

private struct GitHubReleaseResponse: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

struct GitHubReleaseClient: GitHubReleaseChecking {
    func latestRelease(owner: String, repo: String) async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)
        guard let htmlURL = URL(string: response.htmlURL) else {
            throw URLError(.badServerResponse)
        }
        return GitHubRelease(tagName: response.tagName, htmlURL: htmlURL)
    }
}

enum AppUpdateStatus: Sendable, Equatable {
    case notChecked
    case upToDate
    case updateAvailable(version: String, releaseURL: URL)
    case checkFailed
}

struct AppUpdateChecker {
    private let client: GitHubReleaseChecking
    private let owner = "Mshardul"
    private let repo = "Tools"

    init(client: GitHubReleaseChecking = GitHubReleaseClient()) {
        self.client = client
    }

    func checkForUpdate(currentVersion: String) async -> AppUpdateStatus {
        guard let release = try? await client.latestRelease(owner: owner, repo: repo) else {
            return .checkFailed
        }
        // Tag format is "media-grabber-vX.Y.Z" per CLAUDE.md's release convention.
        let bareVersion = release.tagName.replacingOccurrences(of: "media-grabber-v", with: "")
        guard let latest = DottedVersion(parsing: bareVersion),
              let current = DottedVersion(parsing: currentVersion)
        else {
            return .checkFailed
        }
        return current < latest ? .updateAvailable(version: bareVersion, releaseURL: release.htmlURL) : .upToDate
    }
}
