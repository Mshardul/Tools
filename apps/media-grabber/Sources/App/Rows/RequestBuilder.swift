import Foundation
import GrabberKit

struct RunwayOverrides: Equatable {
    var kind: DownloadKind?
    var destFolder: URL?

    init(kind: DownloadKind? = nil, destFolder: URL? = nil) {
        self.kind = kind
        self.destFolder = destFolder
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
            filenameTemplate: prefs.filenameTemplate
        )
    }

    private static func container(for kind: DownloadKind) -> String? {
        if case .video = kind {
            return "mp4"
        }
        return nil
    }
}
