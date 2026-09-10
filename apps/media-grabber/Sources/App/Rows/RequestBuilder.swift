import Foundation
import GrabberKit

struct RunwayOverrides: Equatable {
    var kind: DownloadKind?
    var destFolder: URL?
    var audioLanguage: AudioLanguage?

    init(
        kind: DownloadKind? = nil,
        destFolder: URL? = nil,
        audioLanguage: AudioLanguage? = nil
    ) {
        self.kind = kind
        self.destFolder = destFolder
        self.audioLanguage = audioLanguage
    }
}

enum RequestBuilder {
    static func build(
        from resolved: MediaMetadata,
        prefs: Preferences,
        overrides: RunwayOverrides
    ) -> DownloadRequest {
        let kind = overrides.kind ?? prefs.defaultKind
        return DownloadRequest(
            url: resolved.sourceURL,
            destFolder: overrides.destFolder ?? prefs.lastUsedDownloadFolder,
            kind: kind,
            container: container(for: kind),
            filenameTemplate: prefs.filenameTemplate,
            audioLanguage: overrides.audioLanguage ?? .unspecified
        )
    }

    static func build(
        from entry: PlaylistEntry,
        prefs: Preferences,
        overrides: RunwayOverrides
    ) -> DownloadRequest {
        build(from: prefetch(from: entry), prefs: prefs, overrides: overrides)
    }

    static func prefetch(from entry: PlaylistEntry) -> MediaMetadata {
        MediaMetadata(
            title: entry.title,
            durationSeconds: entry.durationSeconds,
            isPlaylist: false,
            sourceURL: entry.watchURL,
            extractor: entry.extractor
        )
    }

    static func audioLanguage(from track: AudioTrack) -> AudioLanguage {
        guard let code = track.languageCode else {
            return .unspecified
        }
        if track.isOriginal {
            return .original
        }
        return .code(code)
    }

    private static func container(for kind: DownloadKind) -> String? {
        if case .video = kind {
            return "mp4"
        }
        return nil
    }
}
