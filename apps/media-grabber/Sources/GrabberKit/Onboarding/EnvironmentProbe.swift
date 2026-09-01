import Foundation

public struct ToolInfo: Sendable, Equatable {
    public let path: URL
    public let version: String

    public init(path: URL, version: String) {
        self.path = path
        self.version = version
    }
}

public struct EnvironmentReport: Sendable, Equatable {
    public let brew: ToolInfo?
    public let ytDlp: ToolInfo?
    public let ffmpeg: ToolInfo?
    // Resolved from the ffmpeg location, not an independent PATH search — ffprobe ships
    // inside the ffmpeg formula. A missing ffprobe degrades IntegrityCheck, never blocks.
    public let ffprobe: ToolInfo?

    public init(brew: ToolInfo?, ytDlp: ToolInfo?, ffmpeg: ToolInfo?, ffprobe: ToolInfo? = nil) {
        self.brew = brew
        self.ytDlp = ytDlp
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
    }

    public var isReadyForDownloads: Bool {
        ytDlp != nil && ffmpeg != nil
    }
}

public protocol EnvironmentProbing: Sendable {
    func probe() async -> EnvironmentReport
}

public struct EnvironmentProbe: EnvironmentProbing {
    private let runner: ProcessRunning
    private let searchPaths: [URL]
    private let isExecutable: @Sendable (URL) -> Bool

    public init(
        runner: ProcessRunning = ProcessRunner(),
        extraSearchPaths: [URL] = EnvironmentProbe.defaultSearchPaths,
        isExecutable: @escaping @Sendable (URL) -> Bool = { url in
            FileManager.default.isExecutableFile(atPath: url.path)
        }
    ) {
        self.runner = runner
        searchPaths = extraSearchPaths
        self.isExecutable = isExecutable
    }

    public static var defaultSearchPaths: [URL] {
        var paths: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin"),
            URL(fileURLWithPath: "/usr/bin"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin")
        ]
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for entry in envPath.split(separator: ":") where !entry.isEmpty {
            let url = URL(fileURLWithPath: String(entry))
            if !paths.contains(url) {
                paths.append(url)
            }
        }
        return paths
    }

    public func probe() async -> EnvironmentReport {
        async let brew = resolve(name: "brew", versionArgs: ["--version"], parse: Self.parseBrew)
        async let ytDlp = resolve(
            name: "yt-dlp",
            versionArgs: ["--version"],
            parse: Self.parseYtDlp
        )
        async let ffmpeg = resolve(
            name: "ffmpeg",
            versionArgs: ["-version"],
            parse: Self.parseFfmpeg
        )
        let ffmpegInfo = await ffmpeg
        let ffprobeInfo = await resolveFfprobe(besideFfmpeg: ffmpegInfo)
        return await EnvironmentReport(
            brew: brew,
            ytDlp: ytDlp,
            ffmpeg: ffmpegInfo,
            ffprobe: ffprobeInfo
        )
    }

    private func resolveFfprobe(besideFfmpeg ffmpeg: ToolInfo?) async -> ToolInfo? {
        guard let ffmpeg else { return nil }
        let candidate = ffmpeg.path.deletingLastPathComponent().appendingPathComponent("ffprobe")
        guard isExecutable(candidate) else { return nil }
        let execution = runner.run(ProcessLaunch(executableURL: candidate, arguments: ["-version"]))
        var output = ""
        for await line in execution.lines {
            switch line {
            case let .stdout(text), let .stderr(text):
                output += text + "\n"
            }
        }
        let result = await execution.result()
        guard result.exitCode == 0, let version = Self.parseFfmpeg(output) else { return nil }
        return ToolInfo(path: candidate, version: version)
    }

    private func locate(_ name: String) -> URL? {
        for dir in searchPaths {
            let candidate = dir.appendingPathComponent(name)
            if isExecutable(candidate) {
                return candidate
            }
        }
        return nil
    }

    private func resolve(
        name: String,
        versionArgs: [String],
        parse: @Sendable (String) -> String?
    ) async -> ToolInfo? {
        guard let path = locate(name) else { return nil }
        let execution = runner.run(
            ProcessLaunch(executableURL: path, arguments: versionArgs)
        )
        var output = ""
        for await line in execution.lines {
            switch line {
            case let .stdout(text), let .stderr(text):
                output += text + "\n"
            }
        }
        let result = await execution.result()
        guard result.exitCode == 0, let version = parse(output) else { return nil }
        return ToolInfo(path: path, version: version)
    }

    static func parseBrew(_ output: String) -> String? {
        guard let first = firstNonEmptyLine(output) else { return nil }
        let parts = first.split(separator: " ")
        guard parts.count >= 2, parts[0] == "Homebrew" else { return nil }
        return String(parts[1])
    }

    static func parseYtDlp(_ output: String) -> String? {
        guard let first = firstNonEmptyLine(output) else { return nil }
        let token = first.trimmingCharacters(in: .whitespaces)
        guard let start = token.first, start.isNumber || start == "v" else { return nil }
        return token
    }

    static func parseFfmpeg(_ output: String) -> String? {
        guard let first = firstNonEmptyLine(output) else { return nil }
        let parts = first.split(separator: " ")
        guard let idx = parts.firstIndex(of: "version"), idx + 1 < parts.count else {
            return nil
        }
        var token = String(parts[idx + 1])
        if token.hasPrefix("n") {
            token.removeFirst()
        }
        guard let firstChar = token.first, firstChar.isNumber else { return nil }
        return token
    }

    private static func firstNonEmptyLine(_ output: String) -> String? {
        output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}
