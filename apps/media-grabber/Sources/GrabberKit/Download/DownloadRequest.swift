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

    public init(
        url: String,
        destFolder: URL,
        kind: DownloadKind,
        container: String? = nil,
        filenameTemplate: String = "%(title)s.%(ext)s"
    ) {
        self.url = url
        self.destFolder = destFolder
        self.kind = kind
        self.container = container
        self.filenameTemplate = filenameTemplate
    }
}
