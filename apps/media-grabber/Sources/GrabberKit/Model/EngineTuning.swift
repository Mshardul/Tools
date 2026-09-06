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
    public var circuitStrikeThreshold: Int
    public var adaptiveConcurrencyStart: Int
    public var cleanStreakToRaise: Int
    public var networkOfflineGraceSeconds: Int
    public var networkOnlineSettleSeconds: Int
    public var concurrentFragmentsNormal: Int
    public var concurrentFragmentsThrottled: Int

    public init(
        ytDlp: YtDlpTuning,
        backoffLadder: [Int],
        backoffCap: Int,
        circuitStrikeThreshold: Int = 4,
        adaptiveConcurrencyStart: Int = 2,
        cleanStreakToRaise: Int = 5,
        networkOfflineGraceSeconds: Int = 2,
        networkOnlineSettleSeconds: Int = 2,
        concurrentFragmentsNormal: Int = 4,
        concurrentFragmentsThrottled: Int = 1
    ) {
        self.ytDlp = ytDlp
        self.backoffLadder = backoffLadder
        self.backoffCap = backoffCap
        self.circuitStrikeThreshold = circuitStrikeThreshold
        self.adaptiveConcurrencyStart = adaptiveConcurrencyStart
        self.cleanStreakToRaise = cleanStreakToRaise
        self.networkOfflineGraceSeconds = networkOfflineGraceSeconds
        self.networkOnlineSettleSeconds = networkOnlineSettleSeconds
        self.concurrentFragmentsNormal = concurrentFragmentsNormal
        self.concurrentFragmentsThrottled = concurrentFragmentsThrottled
    }

    public static let `default` = EngineTuning(
        ytDlp: .default,
        backoffLadder: [30, 60, 120, 300, 600],
        backoffCap: 600,
        circuitStrikeThreshold: 4,
        adaptiveConcurrencyStart: 2,
        cleanStreakToRaise: 5,
        networkOfflineGraceSeconds: 2,
        networkOnlineSettleSeconds: 2,
        concurrentFragmentsNormal: 4,
        concurrentFragmentsThrottled: 1
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
        let rateLimit = resolveRateLimitTuning(environment)
        return EngineTuning(
            ytDlp: ytDlp,
            backoffLadder: resolveLadder(environment["MG_BACKOFF_LADDER"]),
            backoffCap: intValue("MG_BACKOFF_CAP", EngineTuning.default.backoffCap),
            circuitStrikeThreshold: rateLimit.circuitStrikeThreshold,
            adaptiveConcurrencyStart: rateLimit.adaptiveConcurrencyStart,
            cleanStreakToRaise: rateLimit.cleanStreakToRaise,
            networkOfflineGraceSeconds: rateLimit.networkOfflineGraceSeconds,
            networkOnlineSettleSeconds: rateLimit.networkOnlineSettleSeconds,
            concurrentFragmentsNormal: rateLimit.concurrentFragmentsNormal,
            concurrentFragmentsThrottled: rateLimit.concurrentFragmentsThrottled
        )
    }

    private struct RateLimitTuningValues {
        var circuitStrikeThreshold: Int
        var adaptiveConcurrencyStart: Int
        var cleanStreakToRaise: Int
        var networkOfflineGraceSeconds: Int
        var networkOnlineSettleSeconds: Int
        var concurrentFragmentsNormal: Int
        var concurrentFragmentsThrottled: Int
    }

    private static func resolveRateLimitTuning(_ env: [String: String]) -> RateLimitTuningValues {
        func intValue(_ key: String, _ fallback: Int) -> Int {
            guard let raw = env[key] else { return fallback }
            return Int(raw) ?? fallback
        }
        let base = EngineTuning.default
        return RateLimitTuningValues(
            circuitStrikeThreshold: intValue(
                "MG_CIRCUIT_STRIKE_THRESHOLD",
                base.circuitStrikeThreshold
            ),
            adaptiveConcurrencyStart: intValue(
                "MG_ADAPTIVE_CONCURRENCY_START",
                base.adaptiveConcurrencyStart
            ),
            cleanStreakToRaise: intValue("MG_CLEAN_STREAK_TO_RAISE", base.cleanStreakToRaise),
            networkOfflineGraceSeconds: intValue(
                "MG_NETWORK_OFFLINE_GRACE_SECONDS",
                base.networkOfflineGraceSeconds
            ),
            networkOnlineSettleSeconds: intValue(
                "MG_NETWORK_ONLINE_SETTLE_SECONDS",
                base.networkOnlineSettleSeconds
            ),
            concurrentFragmentsNormal: intValue(
                "MG_CONCURRENT_FRAGMENTS_NORMAL",
                base.concurrentFragmentsNormal
            ),
            concurrentFragmentsThrottled: intValue(
                "MG_CONCURRENT_FRAGMENTS_THROTTLED",
                base.concurrentFragmentsThrottled
            )
        )
    }

    private static func resolveLadder(_ raw: String?) -> [Int] {
        guard let raw else { return EngineTuning.default.backoffLadder }
        let parsed = raw.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !parsed.contains(nil) else { return EngineTuning.default.backoffLadder }
        return parsed.compactMap(\.self)
    }
}
