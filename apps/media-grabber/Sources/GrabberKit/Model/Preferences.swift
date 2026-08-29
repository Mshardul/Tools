import Foundation
import Observation

// String-raw identity only; the Color/Font-bearing Skin lives in the App target.
public enum SkinKind: String, Codable, Sendable, CaseIterable {
    case tapeDeck
    case aurora
}

public enum PaletteKind: String, Codable, Sendable, CaseIterable {
    case auroraMintIris
    case auroraLimeForest
    case auroraMagentaViolet
    case tapeDeckA
    case tapeDeckB
    case tapeDeckC
}

@Observable
public final class Preferences: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Destination

    public var defaultDestFolder: URL {
        get { url(forKey: "defaultDestFolder", default: Self.downloadsFolder) }
        set { setURL(newValue, forKey: "defaultDestFolder") }
    }

    public var lastUsedDestFolder: URL {
        get { url(forKey: "lastUsedDestFolder", default: defaultDestFolder) }
        set { setURL(newValue, forKey: "lastUsedDestFolder") }
    }

    // MARK: - Format

    public var defaultKind: DownloadKind {
        switch defaultAudioOrVideo {
        case .video: .video(maxHeight: defaultMaxHeight)
        case .audio: .audio(codec: defaultAudioCodec)
        }
    }

    private enum KindSelector: String { case video, audio }

    private var defaultAudioOrVideo: KindSelector {
        get {
            (defaults.string(forKey: "mg.defaultKindSelector"))
                .flatMap(KindSelector.init) ?? .video
        }
        set { defaults.set(newValue.rawValue, forKey: "mg.defaultKindSelector") }
    }

    public var defaultMaxHeight: Int {
        get { intValue(forKey: "defaultMaxHeight", default: 1080) }
        set { defaults.set(newValue, forKey: "mg.defaultMaxHeight") }
    }

    public var defaultAudioCodec: AudioCodec {
        get {
            (defaults.string(forKey: "mg.defaultAudioCodec"))
                .flatMap(AudioCodec.init) ?? .m4a
        }
        set { defaults.set(newValue.rawValue, forKey: "mg.defaultAudioCodec") }
    }

    public var outputTemplate: String {
        get { defaults.string(forKey: "mg.outputTemplate") ?? "%(title)s.%(ext)s" }
        set { defaults.set(newValue, forKey: "mg.outputTemplate") }
    }

    // MARK: - Behavior

    public var maxAutoAttempts: Int {
        get { intValue(forKey: "maxAutoAttempts", default: 5) }
        set { defaults.set(min(5, max(1, newValue)), forKey: "mg.maxAutoAttempts") }
    }

    public var verboseLogging: Bool {
        get { defaults.bool(forKey: "mg.verboseLogging") }
        set { defaults.set(newValue, forKey: "mg.verboseLogging") }
    }

    // MARK: - Theme

    public var skin: SkinKind {
        get {
            (defaults.string(forKey: "mg.skin")).flatMap(SkinKind.init) ?? .aurora
        }
        set { defaults.set(newValue.rawValue, forKey: "mg.skin") }
    }

    public var palette: PaletteKind {
        get {
            (defaults.string(forKey: "mg.palette"))
                .flatMap(PaletteKind.init) ?? .auroraMintIris
        }
        set { defaults.set(newValue.rawValue, forKey: "mg.palette") }
    }

    // MARK: - Helpers

    private static var downloadsFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
    }

    private func intValue(forKey name: String, default fallback: Int) -> Int {
        defaults.object(forKey: "mg.\(name)") == nil
            ? fallback
            : defaults.integer(forKey: "mg.\(name)")
    }

    private func url(forKey name: String, default fallback: URL) -> URL {
        guard let path = defaults.string(forKey: "mg.\(name)") else { return fallback }
        return URL(fileURLWithPath: path)
    }

    private func setURL(_ value: URL, forKey name: String) {
        defaults.set(value.path, forKey: "mg.\(name)")
    }
}
