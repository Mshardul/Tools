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
    case jobEnqueued(id: UUID, url: String, queuePosition: Int)
    case jobStartedByScheduler(id: UUID, running: Int, cap: Int)
    case jobPaused(id: UUID)
    case jobResumed(id: UUID)
    case jobRemoved(id: UUID, wasRunning: Bool)
    case jobForceStarted(id: UUID, evicted: UUID?)
    case jobDeferred(id: UUID, until: Date, reason: DeferReason)
    case persistenceLoaded(file: String, count: Int)
    case persistenceCorrupt(file: String)
    case persistenceSchemaAhead(file: String)
    case persistenceWriteFailed(file: String, error: String)
    case persistenceRecovered(file: String)
    case consumerStreamEnded

    var key: String {
        switch self {
        case .appLaunched: "app.launched"
        case .probeCompleted: "probe.completed"
        case .jobStateChanged: "job.state_changed"
        case .processLaunched: "process.launched"
        case .processExited: "process.exited"
        case .jobEnqueued: "job.enqueued"
        case .jobStartedByScheduler: "job.started_by_scheduler"
        case .jobPaused: "job.paused"
        case .jobResumed: "job.resumed"
        case .jobRemoved: "job.removed"
        case .jobForceStarted: "job.force_started"
        case .jobDeferred: "job.deferred"
        case .persistenceLoaded: "persistence.loaded"
        case .persistenceCorrupt: "persistence.corrupt"
        case .persistenceSchemaAhead: "persistence.schema_ahead"
        case .persistenceWriteFailed: "persistence.write_failed"
        case .persistenceRecovered: "persistence.recovered"
        case .consumerStreamEnded: "consumer.stream_ended"
        }
    }

    var category: LogCategory {
        switch self {
        case .appLaunched: .ui
        case .probeCompleted: .engine
        case .jobStateChanged: .engine
        case .processLaunched, .processExited: .engine
        case .jobEnqueued, .jobStartedByScheduler: .scheduler
        case .jobPaused, .jobResumed, .jobRemoved: .engine
        case .jobForceStarted, .jobDeferred: .scheduler
        case .persistenceLoaded, .persistenceCorrupt, .persistenceSchemaAhead,
             .persistenceWriteFailed, .persistenceRecovered: .persistence
        case .consumerStreamEnded: .ui
        }
    }

    var jobID: UUID? {
        switch self {
        case let .jobStateChanged(jobID, _, _): jobID
        case let .jobEnqueued(id, _, _): id
        case let .jobStartedByScheduler(id, _, _): id
        case let .jobPaused(id): id
        case let .jobResumed(id): id
        case let .jobRemoved(id, _): id
        case let .jobForceStarted(id, _): id
        case let .jobDeferred(id, _, _): id
        default: nil
        }
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
        case let .jobEnqueued(_, url, queuePosition):
            ["url": url, "queue_position": String(queuePosition)]
        case let .jobStartedByScheduler(_, running, cap):
            ["running": String(running), "cap": String(cap)]
        case .jobPaused, .jobResumed:
            [:]
        case let .jobRemoved(_, wasRunning):
            ["was_running": wasRunning ? "true" : "false"]
        case let .jobForceStarted(_, evicted):
            ["evicted": evicted?.uuidString ?? ""]
        case let .jobDeferred(_, until, _):
            ["until": ISO8601DateFormatter().string(from: until)]
        case let .persistenceLoaded(file, count):
            ["file": file, "count": String(count)]
        case let .persistenceCorrupt(file):
            ["file": file]
        case let .persistenceSchemaAhead(file):
            ["file": file]
        case let .persistenceWriteFailed(file, error):
            ["file": file, "error": error]
        case let .persistenceRecovered(file):
            ["file": file]
        case .consumerStreamEnded:
            [:]
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
