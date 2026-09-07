import Foundation

public enum AudioFormat: String, Codable, Sendable, CaseIterable {
    case m4a
    case mp3
}

public enum DownloadKind: Codable, Sendable, Equatable {
    case video(maxHeight: Int)
    case audio(format: AudioFormat)
}

public struct DownloadRequest: Codable, Sendable, Equatable {
    public var url: String
    public var destFolder: URL
    public var kind: DownloadKind
    public var container: String?
    public var filenameTemplate: String
    public var audioLanguage: AudioLanguage

    public init(
        url: String,
        destFolder: URL,
        kind: DownloadKind,
        container: String? = nil,
        filenameTemplate: String = "%(title)s.%(ext)s",
        audioLanguage: AudioLanguage = .unspecified
    ) {
        self.url = url
        self.destFolder = destFolder
        self.kind = kind
        self.container = container
        self.filenameTemplate = filenameTemplate
        self.audioLanguage = audioLanguage
    }

    enum CodingKeys: String, CodingKey {
        case url, destFolder, kind, container, filenameTemplate, audioLanguage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        destFolder = try container.decode(URL.self, forKey: .destFolder)
        kind = try container.decode(DownloadKind.self, forKey: .kind)
        self.container = try container.decodeIfPresent(String.self, forKey: .container)
        filenameTemplate = try container.decode(String.self, forKey: .filenameTemplate)
        audioLanguage = try container.decodeIfPresent(AudioLanguage.self, forKey: .audioLanguage)
            ?? .unspecified
    }
}
