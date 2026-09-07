import Foundation

public struct ExtractorContext: Sendable, Equatable {
    public var pluginDirs: [URL]
    public var potBaseURL: URL?
    public var playerClient: String?
    public var cookieArgument: String?

    public static let none = ExtractorContext(
        pluginDirs: [],
        potBaseURL: nil,
        playerClient: nil,
        cookieArgument: nil
    )
}
