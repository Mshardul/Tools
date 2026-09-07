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
        prefs.lastUsedDownloadFolder = dest
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
                filenameTemplate: "%(title)s.%(ext)s"
            )
        )
    }

    func test_fullOverride() {
        let request = RequestBuilder.build(
            from: meta(url: "https://example.com/v"),
            prefs: prefs(),
            overrides: RunwayOverrides(
                kind: .audio(format: .mp3),
                destFolder: overrideDest
            )
        )
        XCTAssertEqual(
            request,
            DownloadRequest(
                url: "https://example.com/v",
                destFolder: overrideDest,
                kind: .audio(format: .mp3),
                container: nil,
                filenameTemplate: "%(title)s.%(ext)s"
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
                filenameTemplate: "%(title)s.%(ext)s"
            )
        )
    }

    func test_audioLanguageOverride_writesOntoRequest() {
        let request = RequestBuilder.build(
            from: meta(),
            prefs: prefs(),
            overrides: RunwayOverrides(audioLanguage: .code("ja"))
        )
        XCTAssertEqual(request.audioLanguage, .code("ja"))
    }

    func test_audioLanguage_fromTrack() {
        XCTAssertEqual(
            RequestBuilder.audioLanguage(from: AudioTrack(
                id: "default",
                languageCode: nil,
                label: "Default",
                isOriginal: false,
                isDefault: true
            )),
            .unspecified
        )
        XCTAssertEqual(
            RequestBuilder.audioLanguage(from: AudioTrack(
                id: "ja|orig",
                languageCode: "ja",
                label: "Japanese (original)",
                isOriginal: true,
                isDefault: true
            )),
            .original
        )
        XCTAssertEqual(
            RequestBuilder.audioLanguage(from: AudioTrack(
                id: "en|dub",
                languageCode: "en",
                label: "English",
                isOriginal: false,
                isDefault: false
            )),
            .code("en")
        )
    }
}
