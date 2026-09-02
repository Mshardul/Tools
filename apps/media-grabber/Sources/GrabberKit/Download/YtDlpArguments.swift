import Foundation

public enum YtDlpArguments {
    static let progressTemplate = "download:MG|%(progress._percent_str)s|"
        + "%(progress._speed_str)s|%(progress._eta_str)s|"
        + "%(progress.downloaded_bytes)s|%(progress.total_bytes)s"

    public static func build(
        for request: DownloadRequest,
        options: GlobalDownloadOptions = .none,
        tuning: YtDlpTuning = .default,
        cookieArgument: String? = nil
    ) -> [String] {
        baseArgv(for: request, tuning: tuning)
            + cookieFlags(cookieArgument, redact: false)
            + globalFlags(options, proxyURL: options.proxyURL)
            + [request.url]
    }

    // Proxy userinfo is masked in the returned proxy URL; the cookie spec is masked too.
    public static func redacted(
        for request: DownloadRequest,
        options: GlobalDownloadOptions = .none,
        tuning: YtDlpTuning = .default,
        cookieArgument: String? = nil
    ) -> [String] {
        baseArgv(for: request, tuning: tuning)
            + cookieFlags(cookieArgument, redact: true)
            + globalFlags(options, proxyURL: options.proxyURL.map(maskUserinfo(in:)))
            + [request.url]
    }

    private static func cookieFlags(_ argument: String?, redact: Bool) -> [String] {
        guard let argument else { return [] }
        return ["--cookies-from-browser", redact ? "<redacted>" : argument]
    }

    private static func baseArgv(for request: DownloadRequest, tuning: YtDlpTuning) -> [String] {
        var argv: [String] = []
        argv += ["-P", request.destFolder.path]
        argv += ["-o", request.filenameTemplate]
        argv += formatSelector(for: request)
        argv += ["--newline", "--progress", "--progress-template", progressTemplate]
        argv += ["--no-playlist"]
        argv += ["--no-warnings"]
        argv += resilienceFlags(tuning)
        return argv
    }

    // Bounded, never infinite — a hard failure must exit yt-dlp and reach the classifier
    // within a knowable time rather than hang inside yt-dlp.
    private static func resilienceFlags(_ tuning: YtDlpTuning) -> [String] {
        [
            "--retries", "\(tuning.retries)",
            "--fragment-retries", "\(tuning.fragmentRetries)",
            "--socket-timeout", "\(tuning.socketTimeout)",
            "--retry-sleep", tuning.retrySleep,
            "--throttled-rate", "\(tuning.throttledRateKBps)K",
            "--file-access-retries", "\(tuning.fileAccessRetries)",
            "--no-part-hint",
            "--sleep-requests", "\(tuning.sleepRequests)",
            "--sleep-interval", "\(tuning.sleepInterval)",
            "--max-sleep-interval", "\(tuning.maxSleepInterval)"
        ]
    }

    private static func globalFlags(
        _ options: GlobalDownloadOptions,
        proxyURL: String?
    ) -> [String] {
        var flags: [String] = []
        if let proxy = proxyURL, !proxy.isEmpty {
            flags += ["--proxy", proxy]
        }
        if options.forceIPv4 {
            flags += ["-4"]
        }
        if options.speedLimitKBps > 0 {
            flags += ["--limit-rate", "\(options.speedLimitKBps)K"]
        }
        return flags
    }

    private static func maskUserinfo(in url: String) -> String {
        guard let at = url.firstIndex(of: "@"),
              let scheme = url.range(of: "://"),
              scheme.upperBound < at
        else { return url }
        return String(url[..<scheme.upperBound]) + "***@" + String(url[url.index(after: at)...])
    }

    private static func formatSelector(for request: DownloadRequest) -> [String] {
        switch request.kind {
        case let .video(maxHeight: height):
            var tokens = [
                "-f",
                "bv*[height<=\(height)][ext=mp4]+ba[ext=m4a]"
                    + "/bv*[height<=\(height)]+ba"
                    + "/b[height<=\(height)]"
            ]
            if let container = request.container {
                tokens += ["--merge-output-format", container]
            }
            return tokens
        case let .audio(format: format):
            return ["-x", "--audio-format", format.rawValue]
        }
    }
}
