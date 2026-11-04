public enum PlayerClientRotation {
    public static let bundled = ["tv", "ios", "tv_embedded", "mweb", "web_safari"]

    public static func client(order: [String], burned: Set<String>) -> String {
        let usable = order.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let remaining = usable.filter { !burned.contains($0) }
        if let next = remaining.first {
            return next
        }
        return usable.last ?? "tv"
    }
}
