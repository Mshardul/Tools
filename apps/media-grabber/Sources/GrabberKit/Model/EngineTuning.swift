import Foundation

// yt-dlp's in-invocation retry / pacing knobs. Env-overridable via MG_YTDLP_* keys, no UI.
public struct YtDlpTuning: Sendable, Equatable {
    public var retries: Int
    public var fragmentRetries: Int
    public var socketTimeout: Int
    public var retrySleep: String
    public var throttledRateKBps: Int
    public var fileAccessRetries: Int
    public var sleepRequests: Int
    public var sleepInterval: Int
    public var maxSleepInterval: Int

    public init(
        retries: Int,
        fragmentRetries: Int,
        socketTimeout: Int,
        retrySleep: String,
        throttledRateKBps: Int,
        fileAccessRetries: Int,
        sleepRequests: Int,
        sleepInterval: Int,
        maxSleepInterval: Int
    ) {
        self.retries = retries
        self.fragmentRetries = fragmentRetries
        self.socketTimeout = socketTimeout
        self.retrySleep = retrySleep
        self.throttledRateKBps = throttledRateKBps
        self.fileAccessRetries = fileAccessRetries
        self.sleepRequests = sleepRequests
        self.sleepInterval = sleepInterval
        self.maxSleepInterval = maxSleepInterval
    }

    public static let `default` = YtDlpTuning(
        retries: 3,
        fragmentRetries: 10,
        socketTimeout: 30,
        retrySleep: "linear=1:10:2",
        throttledRateKBps: 100,
        fileAccessRetries: 5,
        sleepRequests: 1,
        sleepInterval: 1,
        maxSleepInterval: 5
    )
}

// Every retry / pacing number in one env-overridable place, so the values can be tuned or
// A/B'd through the environment without a build. Not exposed in the UI.
public struct EngineTuning: Sendable, Equatable {
    public var ytDlp: YtDlpTuning
    public var backoffLadder: [Int]
    public var backoffCap: Int

    public init(ytDlp: YtDlpTuning, backoffLadder: [Int], backoffCap: Int) {
        self.ytDlp = ytDlp
        self.backoffLadder = backoffLadder
        self.backoffCap = backoffCap
    }

    public static let `default` = EngineTuning(
        ytDlp: .default,
        backoffLadder: [30, 60, 120, 300, 600],
        backoffCap: 600
    )

    // Every unset / malformed key keeps the default.
    public static func resolved(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> EngineTuning {
        func intValue(_ key: String, _ fallback: Int) -> Int {
            guard let raw = environment[key] else { return fallback }
            return Int(raw) ?? fallback
        }
        func stringValue(_ key: String, _ fallback: String) -> String {
            environment[key] ?? fallback
        }
        let base = YtDlpTuning.default
        let ytDlp = YtDlpTuning(
            retries: intValue("MG_YTDLP_RETRIES", base.retries),
            fragmentRetries: intValue("MG_YTDLP_FRAGMENT_RETRIES", base.fragmentRetries),
            socketTimeout: intValue("MG_YTDLP_SOCKET_TIMEOUT", base.socketTimeout),
            retrySleep: stringValue("MG_YTDLP_RETRY_SLEEP", base.retrySleep),
            throttledRateKBps: intValue("MG_YTDLP_THROTTLED_RATE_KBPS", base.throttledRateKBps),
            fileAccessRetries: intValue("MG_YTDLP_FILE_ACCESS_RETRIES", base.fileAccessRetries),
            sleepRequests: intValue("MG_YTDLP_SLEEP_REQUESTS", base.sleepRequests),
            sleepInterval: intValue("MG_YTDLP_SLEEP_INTERVAL", base.sleepInterval),
            maxSleepInterval: intValue("MG_YTDLP_MAX_SLEEP_INTERVAL", base.maxSleepInterval)
        )
        return EngineTuning(
            ytDlp: ytDlp,
            backoffLadder: resolveLadder(environment["MG_BACKOFF_LADDER"]),
            backoffCap: intValue("MG_BACKOFF_CAP", EngineTuning.default.backoffCap)
        )
    }

    private static func resolveLadder(_ raw: String?) -> [Int] {
        guard let raw else { return EngineTuning.default.backoffLadder }
        let parsed = raw.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !parsed.contains(nil) else { return EngineTuning.default.backoffLadder }
        return parsed.compactMap(\.self)
    }
}
