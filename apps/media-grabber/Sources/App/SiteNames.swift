enum SiteNames {
    static func display(_ canonical: String) -> String {
        names[canonical] ?? canonical
    }

    private static let names = [
        "youtube": "YouTube",
        "vimeo.com": "Vimeo",
        "archive.org": "Internet Archive"
    ]
}
