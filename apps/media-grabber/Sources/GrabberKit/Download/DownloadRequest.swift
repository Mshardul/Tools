import Foundation

public enum AudioCodec: String, Codable, Sendable, CaseIterable {
    case m4a
    case mp3
}

public enum DownloadKind: Codable, Sendable, Equatable {
    case video(maxHeight: Int)
    case audio(codec: AudioCodec)
}

public struct DownloadRequest: Codable, Sendable, Equatable {
    public var url: String
    public var destFolder: URL
    public var kind: DownloadKind
    public var container: String?
    public var outputTemplate: String

    public init(
        url: String,
        destFolder: URL,
        kind: DownloadKind,
        container: String? = nil,
        outputTemplate: String = "%(title)s.%(ext)s"
    ) {
        self.url = url
        self.destFolder = destFolder
        self.kind = kind
        self.container = container
        self.outputTemplate = outputTemplate
    }
}
