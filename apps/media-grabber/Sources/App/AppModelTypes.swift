import Foundation
import GrabberKit

#if canImport(AppKit)
    import AppKit
#endif

@MainActor
protocol RevealSink {
    func reveal(_ files: [URL])
}

struct WorkspaceRevealSink: RevealSink {
    func reveal(_ files: [URL]) {
        #if canImport(AppKit)
            guard !files.isEmpty else { return }
            NSWorkspace.shared.activateFileViewerSelecting(files)
        #endif
    }
}

@MainActor
protocol OpenURLSink {
    func open(_ url: URL)
}

struct WorkspaceOpenURLSink: OpenURLSink {
    func open(_ url: URL) {
        #if canImport(AppKit)
            NSWorkspace.shared.open(url)
        #endif
    }
}

enum ResolvedLink: Equatable {
    case video(MediaMetadata)
    case playlist(PlaylistDump)

    var title: String {
        switch self {
        case let .video(meta):
            meta.title
        case let .playlist(dump):
            dump.title
        }
    }
}
