public enum PlayerClientRotation {
    public static let `default` = ["tv", "ios", "tv_embedded", "mweb", "web_safari"]

    public static func client(forAttempt attempt: Int) -> String {
        let list = Self.default
        return list[min(max(attempt, 0), list.count - 1)]
    }
}
