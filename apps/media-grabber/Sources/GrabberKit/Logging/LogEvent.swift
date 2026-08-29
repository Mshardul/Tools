import Foundation

public enum LogLevel: String, Sendable {
    case debug
    case info
    case warn
    case error
}

public enum LogCategory: String, Sendable {
    case engine
    case scheduler
    case deps
    case ui
    case persistence
}

public enum LogEvent: Sendable {
    case appLaunched
    case probeCompleted(url: String, title: String?, ok: Bool)
    case jobStateChanged(jobID: UUID, from: String, to: String)
    case processLaunched(executable: String, argvRedacted: [String])
    case processExited(executable: String, code: Int32)

    var key: String {
        switch self {
        case .appLaunched: "app.launched"
        case .probeCompleted: "probe.completed"
        case .jobStateChanged: "job.state_changed"
        case .processLaunched: "process.launched"
        case .processExited: "process.exited"
        }
    }

    var category: LogCategory {
        switch self {
        case .appLaunched: .ui
        case .probeCompleted: .engine
        case .jobStateChanged: .engine
        case .processLaunched, .processExited: .engine
        }
    }

    var jobID: UUID? {
        if case let .jobStateChanged(jobID, _, _) = self {
            return jobID
        }
        return nil
    }

    var fields: [String: String] {
        switch self {
        case .appLaunched:
            [:]
        case let .probeCompleted(url, title, ok):
            ["url": url, "title": title ?? "", "ok": ok ? "true" : "false"]
        case let .jobStateChanged(_, from, to):
            ["from": from, "to": to]
        case let .processLaunched(executable, argvRedacted):
            ["executable": executable, "argv": argvRedacted.joined(separator: " ")]
        case let .processExited(executable, code):
            ["executable": executable, "code": String(code)]
        }
    }
}

// Spec §8.5: home-dir paths → ~, proxy creds / cookie / username / password stripped.
enum LogRedaction {
    private static let homePrefix = "/Users/"

    static func redact(_ value: String) -> String {
        stripCredentials(rewriteHomePaths(value))
    }

    static func redact(_ fields: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in fields {
            if isSecretKey(key) {
                out[key] = "<redacted>"
            } else {
                out[key] = redact(value)
            }
        }
        return out
    }

    private static func isSecretKey(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return lowered.contains("cookie")
            || lowered.contains("password")
            || lowered.contains("username")
    }

    // /Users/<name>/rest → ~/rest
    static func rewriteHomePaths(_ value: String) -> String {
        guard value.contains(homePrefix) else { return value }
        var result = ""
        var remainder = Substring(value)
        while let range = remainder.range(of: homePrefix) {
            result += remainder[..<range.lowerBound]
            let afterPrefix = remainder[range.upperBound...]
            if let slash = afterPrefix.firstIndex(of: "/") {
                result += "~"
                remainder = afterPrefix[slash...]
            } else {
                result += "~"
                remainder = afterPrefix[afterPrefix.endIndex...]
            }
        }
        result += remainder
        return result
    }

    // scheme://user:pass@host → scheme://host
    static func stripCredentials(_ value: String) -> String {
        guard let schemeRange = value.range(of: "://") else { return value }
        let head = value[..<schemeRange.upperBound]
        let rest = value[schemeRange.upperBound...]
        guard let at = rest.firstIndex(of: "@") else { return value }
        let authority = rest[..<at]
        // Only strip when the userinfo looks like credentials (contains ':' or no '/').
        guard !authority.contains("/") else { return value }
        return String(head) + String(rest[rest.index(after: at)...])
    }
}
