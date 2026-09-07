public enum AudioLanguage: Sendable, Equatable, Codable {
    case unspecified
    case original
    case code(String)
}

public enum AudioLanguagePolicy: String, Codable, Sendable, CaseIterable, Hashable {
    case youtubeDefault
    case original
}

public enum LastAudioLanguage: Codable, Sendable, Equatable {
    case original
    case code(String)
}
