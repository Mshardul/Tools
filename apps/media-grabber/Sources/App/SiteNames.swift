enum SiteNames {
    static func display(_ key: String) -> String {
        names[key.lowercased()] ?? key
    }

    private static let names = [
        "youtube": "YouTube",
        "youtube:tab": "YouTube",
        "youtu.be": "YouTube",
        "m.youtube.com": "YouTube",
        "vimeo": "Vimeo",
        "vimeo.com": "Vimeo",
        "soundcloud": "SoundCloud",
        "archive.org": "Internet Archive",
        "generic": "Web"
    ]
}
