import Foundation

public enum PlaylistLinkKind: Sendable, Equatable {
    case singleVideo
    case youtubePlaylist
    case youtubeUnsupported
}

public enum PlaylistLink {
    public static func classify(_ urlString: String) -> PlaylistLinkKind {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RateHost(urlString: trimmed).canonical == "youtube" else {
            return .singleVideo
        }
        guard let components = URLComponents(string: trimmed) else {
            return .singleVideo
        }

        let path = components.path
        if isWatchPath(path, host: components.host) {
            return .singleVideo
        }
        guard path.contains("/playlist") else {
            return .youtubeUnsupported
        }

        let list = components.queryItems?.first { $0.name == "list" }?.value ?? ""
        return list.hasPrefix("PL") ? .youtubePlaylist : .youtubeUnsupported
    }

    private static func isWatchPath(_ path: String, host: String?) -> Bool {
        let watchLikePrefixes = ["/shorts/", "/live/", "/embed/"]
        if path.contains("/watch") || watchLikePrefixes.contains(where: path.hasPrefix) {
            return true
        }
        return host?.lowercased() == "youtu.be" && path != "/playlist"
    }
}
