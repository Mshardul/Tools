@testable import GrabberKit
@testable import MediaGrabber
import XCTest

final class RequestBuilderTests: XCTestCase {
    private let dest = URL(fileURLWithPath: "/tmp/prefs")
    private let overrideDest = URL(fileURLWithPath: "/tmp/override")

    private func meta(url: String = "https://archive.org/details/x") -> MediaMetadata {
        MediaMetadata(
            title: "Clip",
            durationSeconds: 10,
            isPlaylist: false,
            sourceURL: url
        )
    }

    private func prefs() -> Preferences {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "mg.rb.\(UUID().uuidString)")!)
        prefs.lastUsedDestFolder = dest
        return prefs
    }

    func test_prefsOnly_noOverrides() {
        let request = RequestBuilder.build(
            from: meta(),
            prefs: prefs(),
            overrides: RunwayOverrides()
        )
        XCTAssertEqual(
            request,
            DownloadRequest(
                url: "https://archive.org/details/x",
                destFolder: dest,
                kind: .video(maxHeight: 1080),
                container: "mp4",
                outputTemplate: "%(title)s.%(ext)s"
            )
        )
    }

    func test_fullOverride() {
        let request = RequestBuilder.build(
            from: meta(url: "https://example.com/v"),
            prefs: prefs(),
            overrides: RunwayOverrides(
                kind: .audio(codec: .mp3),
                destFolder: overrideDest
            )
        )
        XCTAssertEqual(
            request,
            DownloadRequest(
                url: "https://example.com/v",
                destFolder: overrideDest,
                kind: .audio(codec: .mp3),
                container: nil,
                outputTemplate: "%(title)s.%(ext)s"
            )
        )
    }

    func test_partialOverride() {
        let request = RequestBuilder.build(
            from: meta(),
            prefs: prefs(),
            overrides: RunwayOverrides(kind: .video(maxHeight: 720), destFolder: nil)
        )
        XCTAssertEqual(
            request,
            DownloadRequest(
                url: "https://archive.org/details/x",
                destFolder: dest,
                kind: .video(maxHeight: 720),
                container: "mp4",
                outputTemplate: "%(title)s.%(ext)s"
            )
        )
    }
}
