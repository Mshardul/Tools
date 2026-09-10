import Foundation

public struct PlaylistDump: Sendable, Equatable {
    public var title: String
    public var uploader: String?
    public var extractor: String?
    public var sourceURL: String
    public var entries: [PlaylistEntry]
}

public struct PlaylistEntry: Sendable, Equatable {
    public var watchURL: String
    public var title: String
    public var durationSeconds: Int?
    public var thumbnailURL: String?
    public var extractor: String?
    public var playlistIndex: Int
}

public extension PlaylistDump {
    static func decode(
        _ stdout: String,
        pasteURL: String
    ) -> Result<PlaylistDump, MetadataError> {
        guard
            let data = stdout.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let title = object["title"] as? String,
            let rawEntries = object["entries"] as? [[String: Any]]
        else {
            return .failure(.malformedOutput)
        }

        let extractor = object["extractor"] as? String
        let entries = decodeEntries(rawEntries, playlistExtractor: extractor)
        guard !entries.isEmpty else {
            return .failure(.malformedOutput)
        }

        return .success(PlaylistDump(
            title: title,
            uploader: object["uploader"] as? String,
            extractor: extractor,
            sourceURL: (object["webpage_url"] as? String) ?? pasteURL,
            entries: entries
        ))
    }

    static func decodeForTest(
        _ stdout: String,
        pasteURL: String
    ) -> Result<PlaylistDump, MetadataError> {
        decode(stdout, pasteURL: pasteURL)
    }

    private static func decodeEntries(
        _ rawEntries: [[String: Any]],
        playlistExtractor: String?
    ) -> [PlaylistEntry] {
        var entries: [PlaylistEntry] = []
        for rawEntry in rawEntries {
            guard let entry = decodeEntry(
                rawEntry,
                playlistExtractor: playlistExtractor,
                fallbackIndex: entries.count + 1
            ) else {
                continue
            }
            entries.append(entry)
        }
        return entries
    }

    private static func decodeEntry(
        _ object: [String: Any],
        playlistExtractor: String?,
        fallbackIndex: Int
    ) -> PlaylistEntry? {
        guard
            (object["_type"] as? String) != "playlist",
            let watchURL = watchURL(from: object),
            let title = title(from: object)
        else {
            return nil
        }

        return PlaylistEntry(
            watchURL: watchURL,
            title: title,
            durationSeconds: durationSeconds(object),
            thumbnailURL: object["thumbnail"] as? String,
            extractor: extractor(from: object, playlistExtractor: playlistExtractor),
            playlistIndex: integer(object["playlist_index"]) ?? fallbackIndex
        )
    }

    private static func watchURL(from object: [String: Any]) -> String? {
        if let webpageURL = object["webpage_url"] as? String {
            return webpageURL
        }
        if let url = object["url"] as? String, url.hasPrefix("http") {
            return url
        }
        guard let id = object["id"] as? String else {
            return nil
        }
        return "https://www.youtube.com/watch?v=\(id)"
    }

    private static func title(from object: [String: Any]) -> String? {
        if let title = object["title"] as? String {
            return title
        }
        return object["id"] as? String
    }

    private static func extractor(
        from object: [String: Any],
        playlistExtractor: String?
    ) -> String? {
        (object["ie_key"] as? String)
            ?? (object["extractor"] as? String)
            ?? playlistExtractor
    }

    private static func durationSeconds(_ object: [String: Any]) -> Int? {
        guard let value = object["duration"] else { return nil }
        if let number = value as? Double {
            return Int(number.rounded())
        }
        if let number = value as? Int {
            return number
        }
        if let number = value as? NSNumber {
            return Int(number.doubleValue.rounded())
        }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? Int {
            return number
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }
}
