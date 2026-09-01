import Foundation

public struct FailurePresentation: Sendable, Equatable {
    // One plain-English sentence — no error code, no yt-dlp jargon.
    public let sentence: String
    // Row actions offered beyond the always-present remove / openInBrowser / showLog.
    public let offeredActions: Set<RowAction>

    public init(sentence: String, offeredActions: Set<RowAction>) {
        self.sentence = sentence
        self.offeredActions = offeredActions
    }

    public static func `for`(_ errorClass: ErrorClass) -> FailurePresentation {
        FailurePresentation(
            sentence: sentence(for: errorClass),
            offeredActions: actions(for: errorClass)
        )
    }

    private static func sentence(for errorClass: ErrorClass) -> String {
        if case let .unknown(raw) = errorClass {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return fixedSentences[errorClass.key] ?? "This download failed."
    }

    private static let fixedSentences: [String: String] = [
        "rate_limited": "The site is limiting how fast we can download right now.",
        "geo_blocked": "This video isn't available in your region.",
        "private": "This video is private.",
        "unavailable": "This video is no longer available.",
        "age_restricted": "This video is age-restricted and needs you to be signed in.",
        "network_down": "No internet connection.",
        "cookie_read_failed": "Couldn't read your browser's sign-in.",
        "disk_full": "The disk is full.",
        "permission_denied": "The download folder isn't writable.",
        "incomplete": "The download kept ending early.",
        "dep_missing": "The downloader needs reinstalling."
    ]

    private static let noRetryKeys: Set<String> = [
        "geo_blocked", "private", "unavailable", "age_restricted", "dep_missing"
    ]

    private static func actions(for errorClass: ErrorClass) -> Set<RowAction> {
        noRetryKeys.contains(errorClass.key) ? [] : [.retry]
    }
}
