import Foundation

// The substring -> ErrorClass table shared by the download and probe classifiers so they agree by construction.
public enum ErrorSignatures {
    // Ordered, first case-insensitive substring match wins; networkDown is caught by ProgressParser before this table.
    static let table: [(errorClass: ErrorClass, substrings: [String])] = [
        (.rateLimited(), [
            "HTTP Error 429",
            "Too Many Requests",
            "below throttle limit",
            "The download speed is below the minimum"
        ]),
        (.geoBlocked, [
            "available in your country",
            "blocked it in your country",
            "geo restrict"
        ]),
        (.private, [
            "Private video",
            "Sign in if you've been granted access to this video"
        ]),
        (.unavailable, [
            "Video unavailable",
            "This video is unavailable",
            "This video is not available",
            "has been removed",
            "no longer available"
        ]),
        (.ageRestricted, [
            "Sign in to confirm your age",
            "age-restricted",
            "confirm your age"
        ]),
        (.sabrGated, [
            "only images are available",
            "sabr"
        ]),
        (.formatsMissing, [
            "requested format is not available"
        ]),
        (.botCheck, [
            "Sign in to confirm you're not a bot",
            "confirm you're not a bot",
            "page needs to be reloaded",
            "unable to extract uploader id",
            "HTTP Error 403",
            "This content isn't available, try again later"
        ])
    ]

    // AND within a group, OR across groups; checked before `table` so a cookie-read error outranks the video state.
    static let cookieReadFailedGroups: [[String]] = [
        ["could not find", "cookies database"],
        ["permission denied", "cookies"],
        ["failed to decrypt"],
        ["unable to open database file", "cookies"],
        ["could not copy", "cookie"],
        ["you must provide at least one", "cookies"]
    ]

    static func firstMatch(in line: String) -> ErrorClass? {
        let lowered = line.lowercased()
        if matchesCookieReadFailed(lowered) {
            return .cookieReadFailed
        }
        return table.first { entry in
            entry.substrings.contains { lowered.contains($0.lowercased()) }
        }?.errorClass
    }

    private static func matchesCookieReadFailed(_ lowered: String) -> Bool {
        cookieReadFailedGroups.contains { group in
            group.allSatisfy { lowered.contains($0) }
        }
    }

    // A trailing "Retry-After: <int>" — integer seconds only; an HTTP-date value yields nil.
    static func retryAfterSeconds(in line: String) -> Int? {
        guard let range = line.range(of: "Retry-After:", options: .caseInsensitive) else {
            return nil
        }
        let tail = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        guard tail.first?.isNumber == true else { return nil }
        let digits = tail.prefix { $0.isNumber }
        return Int(digits)
    }
}
