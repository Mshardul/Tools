import Foundation

public enum FormatAvailability: Sendable, Equatable {
    case unknown
    case listed
}

public struct AudioTrack: Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let languageCode: String?
    public let label: String
    public let isOriginal: Bool
    public let isDefault: Bool

    public init(
        id: String,
        languageCode: String?,
        label: String,
        isOriginal: Bool,
        isDefault: Bool
    ) {
        self.id = id
        self.languageCode = languageCode
        self.label = label
        self.isOriginal = isOriginal
        self.isDefault = isDefault
    }
}

enum FormatCatalog {
    struct ParsedFormats {
        var availability: FormatAvailability
        var videoHeights: [Int]
        var audioTracks: [AudioTrack]
    }

    static func parseJSONObject(_ object: [String: Any]) -> ParsedFormats {
        let original = object["original_language"] as? String
        guard let raw = object["formats"] else {
            return ParsedFormats(availability: .unknown, videoHeights: [], audioTracks: [])
        }
        guard let formats = raw as? [[String: Any]] else {
            return ParsedFormats(availability: .unknown, videoHeights: [], audioTracks: [])
        }
        return parse(formats: formats, originalLanguage: original)
    }

    static func parse(formats: [[String: Any]], originalLanguage: String?) -> ParsedFormats {
        let heights = Set(formats.compactMap(videoHeight)).sorted(by: >)
        let collected = collectAudio(formats: formats, originalLanguage: originalLanguage)
        return ParsedFormats(
            availability: .listed,
            videoHeights: heights,
            audioTracks: finalizeTracks(collected)
        )
    }

    private static func videoHeight(_ row: [String: Any]) -> Int? {
        guard let codec = row["vcodec"] as? String, codec != "none" else { return nil }
        return intValue(row["height"])
    }

    private static func collectAudio(
        formats: [[String: Any]],
        originalLanguage: String?
    ) -> [(track: AudioTrack, preference: Int)] {
        var seen: Set<String> = []
        var result: [(track: AudioTrack, preference: Int)] = []
        for row in formats {
            guard let track = audioTrack(from: row, originalLanguage: originalLanguage) else {
                continue
            }
            if seen.contains(track.id) {
                continue
            }
            seen.insert(track.id)
            result.append((track, intValue(row["language_preference"]) ?? Int.min))
        }
        return result
    }

    private static func audioTrack(
        from row: [String: Any],
        originalLanguage: String?
    ) -> AudioTrack? {
        guard let codec = row["acodec"] as? String, codec != "none" else { return nil }
        let language = row["language"] as? String
        let note = row["format_note"] as? String ?? ""
        let isOriginal = note.localizedCaseInsensitiveContains("original")
            || (language != nil && language == originalLanguage)
        let code = language
        let id = "\(code ?? "und")|\(isOriginal ? "orig" : "dub")"
        return AudioTrack(
            id: id,
            languageCode: code,
            label: label(row: row, isOriginal: isOriginal),
            isOriginal: isOriginal,
            isDefault: false
        )
    }

    private static func finalizeTracks(
        _ collected: [(track: AudioTrack, preference: Int)]
    ) -> [AudioTrack] {
        let tracks = collected.map(\.track)
        if tracks.isEmpty || tracks.allSatisfy({ $0.languageCode == nil && !$0.isOriginal }) {
            return [AudioTrack(
                id: "default",
                languageCode: nil,
                label: "Default",
                isOriginal: false,
                isDefault: true
            )]
        }
        return electDefault(collected)
    }

    private static func electDefault(
        _ collected: [(track: AudioTrack, preference: Int)]
    ) -> [AudioTrack] {
        var best = 0
        var index = 1
        while index < collected.count {
            if collected[index].preference > collected[best].preference {
                best = index
            }
            index += 1
        }
        return collected.enumerated().map { index, item in
            AudioTrack(
                id: item.track.id,
                languageCode: item.track.languageCode,
                label: item.track.label,
                isOriginal: item.track.isOriginal,
                isDefault: index == best
            )
        }
    }

    private static func label(row: [String: Any], isOriginal: Bool) -> String {
        if let name = displayName(row), !name.isEmpty {
            return annotateOriginal(name, isOriginal)
        }
        if let note = row["format_note"] as? String, !note.isEmpty, !isTechnical(note) {
            return annotateOriginal(note, isOriginal)
        }
        if let language = row["language"] as? String, !language.isEmpty {
            return annotateOriginal(language, isOriginal)
        }
        return annotateOriginal("Default", isOriginal)
    }

    private static func displayName(_ row: [String: Any]) -> String? {
        guard let track = row["audio_track"] as? [String: Any] else { return nil }
        return track["display_name"] as? String
    }

    private static func isTechnical(_ note: String) -> Bool {
        let lowered = note.lowercased()
        return lowered.contains(",") || lowered.hasPrefix("default")
    }

    private static func annotateOriginal(_ label: String, _ isOriginal: Bool) -> String {
        guard isOriginal else { return label }
        if label.localizedCaseInsensitiveContains("original") {
            return label
        }
        return label + " (original)"
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let value = any as? Int {
            return value
        }
        if let value = any as? Double {
            return Int(value)
        }
        if let value = any as? NSNumber {
            return value.intValue
        }
        return nil
    }
}

public enum VideoQualityOptions {
    private static let ladder = [2160, 1440, 1080, 720, 480]

    public static func offered(from meta: MediaMetadata) -> [Int] {
        switch meta.formatAvailability {
        case .unknown:
            ladder + [.max]
        case .listed:
            listedOffered(heights: meta.videoHeights)
        }
    }

    public static func seed(last: Int?, defaultHeight: Int, offered: [Int]) -> Int {
        if let last, offered.contains(last) {
            return last
        }
        if offered.contains(defaultHeight) {
            return defaultHeight
        }
        return offered.filter { $0 != .max }.max() ?? .max
    }

    private static func listedOffered(heights: [Int]) -> [Int] {
        guard let maxHeight = heights.max() else {
            return [.max]
        }
        return ladder.filter { $0 <= maxHeight } + [.max]
    }
}

public enum AudioLanguageSeed {
    public static func pick(
        tracks: [AudioTrack],
        last: LastAudioLanguage?,
        policy: AudioLanguagePolicy
    ) -> AudioTrack {
        if case .original = last, let track = tracks.first(where: \.isOriginal) {
            return track
        }
        if case let .code(code) = last, let track = track(forCode: code, in: tracks) {
            return track
        }
        if policy == .original, let track = tracks.first(where: \.isOriginal) {
            return track
        }
        if let track = tracks.first(where: \.isDefault) {
            return track
        }
        return AudioTrack(
            id: "default",
            languageCode: nil,
            label: "Default",
            isOriginal: false,
            isDefault: true
        )
    }

    private static func track(forCode code: String, in tracks: [AudioTrack]) -> AudioTrack? {
        if let dub = tracks.first(where: { $0.languageCode == code && !$0.isOriginal }) {
            return dub
        }
        return tracks.first { $0.languageCode == code }
    }
}
