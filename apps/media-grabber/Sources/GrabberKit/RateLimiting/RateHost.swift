import Foundation

public struct RateHost: Hashable, Sendable, CustomStringConvertible {
    public let canonical: String

    public var description: String {
        canonical
    }

    public static let unresolved = RateHost(canonical: "unresolved")

    private init(canonical: String) {
        self.canonical = canonical
    }

    public init(urlString: String) {
        guard let host = URLComponents(string: urlString)?.host?.lowercased(), !host.isEmpty else {
            self = .unresolved
            return
        }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        canonical = Self.aliases[bare] ?? bare
    }

    private static let aliases: [String: String] = [
        "youtube.com": "youtube",
        "youtu.be": "youtube",
        "m.youtube.com": "youtube",
        "music.youtube.com": "youtube",
        "gaming.youtube.com": "youtube",
        "youtube-nocookie.com": "youtube"
    ]
}
