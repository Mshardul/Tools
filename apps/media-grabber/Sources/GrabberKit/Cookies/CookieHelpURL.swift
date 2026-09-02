import Foundation

public enum CookieHelpURL {
    public static func url(forBrowserKey key: String) -> URL {
        guard let url = URL(string: base + anchor(forBrowserKey: key)) else {
            preconditionFailure("cookie help URL is a fixed literal and must parse")
        }
        return url
    }

    private static let base = "https://github.com/yt-dlp/yt-dlp/wiki/FAQ"

    private static func anchor(forBrowserKey _: String) -> String {
        "#how-do-i-pass-cookies-to-yt-dlp"
    }
}
