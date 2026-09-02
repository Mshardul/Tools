import Foundation

// The substring -> ErrorClass data table, shared by ProgressParser.classifyStderr (download side)
// and MetadataProbe's classifier so the two agree by construction, not by two hand-kept lists.
public enum ErrorSignatures {
    // Ordered: the first class with any contained substring (case-insensitive) wins.
    // networkDown is handled by ProgressParser's own signature list before this table.
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
        ])
    ]

    // AND within a group, OR across groups. Checked before `table` so a cookie-read error
    // on a private video classifies as the cookie problem, not the video state.
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
