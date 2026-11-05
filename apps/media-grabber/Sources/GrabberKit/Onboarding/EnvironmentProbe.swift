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
    // Resolved from the ffmpeg location, not a PATH search; a missing ffprobe degrades IntegrityCheck, never blocks.
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

    public var ytDlpDriftVerdict: YtDlpDriftVerdict? {
        guard let ytDlp else { return nil }
        return DottedVersion.driftVerdict(
            installedRaw: ytDlp.version,
            minimumRaw: EngineTuning.default.minimumYtDlpVersion
        )
    }
}

public protocol EnvironmentProbing: Sendable {
    func probe() async -> EnvironmentReport
}

public struct EnvironmentProbe: EnvironmentProbing {
    private let runner: ProcessRunning
    private let tools: ManagedTools
    private let isExecutable: @Sendable (URL) -> Bool

    public init(
        runner: ProcessRunning = ProcessRunner(),
        tools: ManagedTools = .live(),
        isExecutable: @escaping @Sendable (URL) -> Bool = { url in
            FileManager.default.isExecutableFile(atPath: url.path)
        }
    ) {
        self.runner = runner
        self.tools = tools
        self.isExecutable = isExecutable
    }

    public func probe() async -> EnvironmentReport {
        async let bundled = inspect(tools.bundledYtDlp, arguments: ["--version"], parse: Self.parseYtDlp)
        async let updated = inspect(tools.updatedYtDlp, arguments: ["--version"], parse: Self.parseYtDlp)
        async let ffmpeg = inspect(tools.ffmpegURL, arguments: ["-version"], parse: Self.parseFfmpeg)
        async let ffprobe = inspect(tools.ffprobeURL, arguments: ["-version"], parse: Self.parseFfmpeg)
        let ytDlp = await Self.preferNewer(bundled, updated)
        return await EnvironmentReport(brew: nil, ytDlp: ytDlp, ffmpeg: ffmpeg, ffprobe: ffprobe)
    }

    static func preferNewer(_ bundled: ToolInfo?, _ updated: ToolInfo?) -> ToolInfo? {
        switch (bundled, updated) {
        case let (included?, replacement?):
            guard let includedVersion = DottedVersion(parsing: included.version),
                  let replacementVersion = DottedVersion(parsing: replacement.version),
                  replacementVersion > includedVersion
            else { return included }
            return replacement
        case let (included?, nil):
            return included
        case let (nil, replacement?):
            return replacement
        default:
            return nil
        }
    }

    private func inspect(
        _ path: URL,
        arguments: [String],
        parse: @Sendable (String) -> String?
    ) async -> ToolInfo? {
        guard isExecutable(path) else { return nil }
        let execution = runner.run(
            ProcessLaunch(executableURL: path, arguments: arguments)
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
