import Foundation

public struct DottedVersion: Sendable, Equatable, Comparable {
    private let components: [Int]

    public init?(parsing raw: String) {
        var token = raw.trimmingCharacters(in: .whitespaces)
        if token.hasPrefix("v") {
            token.removeFirst()
        }
        guard !token.isEmpty else { return nil }
        let parts = token.split(separator: ".")
        guard !parts.isEmpty else { return nil }
        var parsed: [Int] = []
        for part in parts {
            guard let value = Int(part) else { return nil }
            parsed.append(value)
        }
        components = parsed
    }

    public static func < (lhs: DottedVersion, rhs: DottedVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0 ..< count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}

public enum YtDlpDriftVerdict: Sendable, Equatable {
    case current
    case drift(installed: String, minimum: String)
    case unknown(raw: String)

    public static func driftVerdict(installedRaw: String, minimumRaw: String) -> YtDlpDriftVerdict {
        guard let installed = DottedVersion(parsing: installedRaw) else {
            return .unknown(raw: installedRaw)
        }
        guard let minimum = DottedVersion(parsing: minimumRaw) else {
            return .unknown(raw: installedRaw)
        }
        return installed < minimum ? .drift(installed: installedRaw, minimum: minimumRaw) : .current
    }
}

public extension DottedVersion {
    static func driftVerdict(installedRaw: String, minimumRaw: String) -> YtDlpDriftVerdict {
        YtDlpDriftVerdict.driftVerdict(installedRaw: installedRaw, minimumRaw: minimumRaw)
    }
}
