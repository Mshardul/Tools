import Foundation
import Observation

// String-raw identity only; the Color/Font-bearing Theme lives in the App target.
public enum ThemeKind: String, Codable, Sendable, CaseIterable {
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

    public var defaultDownloadFolder: URL {
        get { url(forKey: "defaultDownloadFolder", default: Self.downloadsFolder) }
        set { setURL(newValue, forKey: "defaultDownloadFolder") }
    }

    public var lastUsedDownloadFolder: URL {
        get { url(forKey: "lastUsedDownloadFolder", default: defaultDownloadFolder) }
        set { setURL(newValue, forKey: "lastUsedDownloadFolder") }
    }

    // MARK: - Format

    public var defaultKind: DownloadKind {
        switch defaultMediaType {
        case .video: .video(maxHeight: defaultVideoHeight)
        case .audio: .audio(format: defaultAudioFormat)
        }
    }

    public var defaultMediaType: MediaType {
        get {
            (defaults.string(forKey: "mg.defaultMediaType"))
                .flatMap(MediaType.init) ?? .video
        }
        set { defaults.set(newValue.rawValue, forKey: "mg.defaultMediaType") }
    }

    public var defaultVideoHeight: Int {
        get { intValue(forKey: "defaultVideoHeight", default: 1080) }
        set { defaults.set(newValue, forKey: "mg.defaultVideoHeight") }
    }

    public var defaultAudioFormat: AudioFormat {
        get {
            (defaults.string(forKey: "mg.defaultAudioFormat"))
                .flatMap(AudioFormat.init) ?? .m4a
        }
        set { defaults.set(newValue.rawValue, forKey: "mg.defaultAudioFormat") }
    }

    public var filenameTemplate: String {
        get { defaults.string(forKey: "mg.filenameTemplate") ?? "%(title)s.%(ext)s" }
        set { defaults.set(newValue, forKey: "mg.filenameTemplate") }
    }

    // MARK: - Behavior

    public var maxAutoRetries: Int {
        get { intValue(forKey: "maxAutoRetries", default: 5) }
        set { defaults.set(min(5, max(1, newValue)), forKey: "mg.maxAutoRetries") }
    }

    // Gates concurrent downloads only, not probes. DebugFlags.concurrencyCapOverride wins.
    public var maxConcurrentDownloads: Int {
        get { intValue(forKey: "maxConcurrentDownloads", default: 3) }
        set { defaults.set(min(6, max(1, newValue)), forKey: "mg.maxConcurrentDownloads") }
    }

    public var verboseLogging: Bool {
        get { defaults.bool(forKey: "mg.verboseLogging") }
        set { defaults.set(newValue, forKey: "mg.verboseLogging") }
    }

    // MARK: - Clipboard

    public var detectClipboardLinks: Bool {
        get {
            defaults.object(forKey: "mg.detectClipboardLinks") == nil
                ? true
                : defaults.bool(forKey: "mg.detectClipboardLinks")
        }
        set { defaults.set(newValue, forKey: "mg.detectClipboardLinks") }
    }

    // MARK: - Network

    public var proxyURL: String? {
        get { defaults.string(forKey: "mg.proxyURL") }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                defaults.removeObject(forKey: "mg.proxyURL")
            } else {
                defaults.set(trimmed, forKey: "mg.proxyURL")
            }
        }
    }

    public var forceIPv4: Bool {
        get { defaults.bool(forKey: "mg.forceIPv4") }
        set { defaults.set(newValue, forKey: "mg.forceIPv4") }
    }

    public var speedLimitKBps: Int {
        get { intValue(forKey: "speedLimitKBps", default: 0) }
        set { defaults.set(min(100_000, max(0, newValue)), forKey: "mg.speedLimitKBps") }
    }

    // MARK: - Cookies

    public var cookiesFromBrowser: CookieSource {
        get {
            guard let data = defaults.data(forKey: "mg.cookiesFromBrowser"),
                  let decoded = try? JSONDecoder().decode(CookieSource.self, from: data)
            else {
                return .none
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else {
                defaults.removeObject(forKey: "mg.cookiesFromBrowser")
                return
            }
            defaults.set(data, forKey: "mg.cookiesFromBrowser")
        }
    }

    // MARK: - Runway last-selected

    public var lastVideoHeight: Int? {
        get {
            defaults.object(forKey: "mg.lastVideoHeight") == nil
                ? nil
                : defaults.integer(forKey: "mg.lastVideoHeight")
        }
        set {
            guard let value = newValue else {
                defaults.removeObject(forKey: "mg.lastVideoHeight")
                return
            }
            defaults.set(value, forKey: "mg.lastVideoHeight")
        }
    }

    public var lastMediaType: MediaType? {
        get { defaults.string(forKey: "mg.lastMediaType").flatMap(MediaType.init) }
        set {
            guard let value = newValue else {
                defaults.removeObject(forKey: "mg.lastMediaType")
                return
            }
            defaults.set(value.rawValue, forKey: "mg.lastMediaType")
        }
    }

    public var lastAudioFormat: AudioFormat? {
        get { defaults.string(forKey: "mg.lastAudioFormat").flatMap(AudioFormat.init) }
        set {
            guard let value = newValue else {
                defaults.removeObject(forKey: "mg.lastAudioFormat")
                return
            }
            defaults.set(value.rawValue, forKey: "mg.lastAudioFormat")
        }
    }

    // MARK: - Theme

    public var theme: ThemeKind {
        get {
            (defaults.string(forKey: "mg.theme")).flatMap(ThemeKind.init) ?? .aurora
        }
        set { defaults.set(newValue.rawValue, forKey: "mg.theme") }
    }

    public var palette: PaletteKind {
        get {
            (defaults.string(forKey: "mg.palette"))
                .flatMap(PaletteKind.init) ?? .auroraMintIris
        }
        set { defaults.set(newValue.rawValue, forKey: "mg.palette") }
    }

    // MARK: - Reset

    public func resetToDefaults() {
        for key in Self.ownedKeys {
            defaults.removeObject(forKey: key)
        }
    }

    private static let ownedKeys = [
        "mg.defaultDownloadFolder", "mg.lastUsedDownloadFolder", "mg.defaultMediaType",
        "mg.defaultVideoHeight", "mg.defaultAudioFormat", "mg.filenameTemplate",
        "mg.maxAutoRetries", "mg.maxConcurrentDownloads", "mg.verboseLogging",
        "mg.theme", "mg.palette", "mg.detectClipboardLinks", "mg.proxyURL",
        "mg.forceIPv4", "mg.speedLimitKBps", "mg.lastVideoHeight",
        "mg.lastMediaType", "mg.lastAudioFormat", "mg.cookiesFromBrowser"
    ]

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
