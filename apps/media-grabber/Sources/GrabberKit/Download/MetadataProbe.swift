import Foundation

public struct MediaMetadata: Sendable, Equatable {
    public let title: String
    public let durationSeconds: Int?
    public let isPlaylist: Bool
    public let sourceURL: String

    public init(title: String, durationSeconds: Int?, isPlaylist: Bool, sourceURL: String) {
        self.title = title
        self.durationSeconds = durationSeconds
        self.isPlaylist = isPlaylist
        self.sourceURL = sourceURL
    }
}

public enum MetadataError: Error, Sendable, Equatable {
    case badURL
    case unsupported
    case unavailable
    case network
    case ytDlpMissing
    case malformedOutput
    case unknown(raw: String)
}

public protocol MetadataProbing: Sendable {
    func probe(_ url: String) async -> Result<MediaMetadata, MetadataError>
}

public actor MetadataProbe: MetadataProbing {
    private let ytDlpURL: URL
    private let runner: ProcessRunning

    // Actors are reentrant across `await`, so chain probes explicitly to serialize.
    private var tail: Task<Void, Never> = Task {}

    public init(ytDlpURL: URL, runner: ProcessRunning = ProcessRunner()) {
        self.ytDlpURL = ytDlpURL
        self.runner = runner
    }

    public func probe(_ url: String) async -> Result<MediaMetadata, MetadataError> {
        let predecessor = tail
        let work = Task { () -> Result<MediaMetadata, MetadataError> in
            await predecessor.value
            return await self.runProbe(url)
        }
        tail = Task { _ = await work.value }
        return await work.value
    }

    private func runProbe(_ url: String) async -> Result<MediaMetadata, MetadataError> {
        let execution = runner.run(ProcessLaunch(
            executableURL: ytDlpURL,
            arguments: ["-J", "--no-warnings", "--no-playlist", url]
        ))

        var stdout = ""
        var stderr = ""
        for await line in execution.lines {
            switch line {
            case let .stdout(text): stdout += text + "\n"
            case let .stderr(text): stderr += text + "\n"
            }
        }
        let result = await execution.result()

        guard result.exitCode == 0 else {
            return .failure(classify(stderr: stderr, exitCode: result.exitCode))
        }
        return decode(stdout, sourceURL: url)
    }

    private func decode(
        _ stdout: String,
        sourceURL: String
    ) -> Result<MediaMetadata, MetadataError> {
        struct Payload: Decodable {
            let title: String?
            let duration: Double?
            // swiftlint:disable:next identifier_name
            let _type: String?
        }
        guard
            let data = stdout.data(using: .utf8),
            let payload = try? JSONDecoder().decode(Payload.self, from: data),
            let title = payload.title
        else {
            return .failure(.malformedOutput)
        }
        return .success(MediaMetadata(
            title: title,
            durationSeconds: payload.duration.map { Int($0.rounded()) },
            isPlaylist: payload._type == "playlist",
            sourceURL: sourceURL
        ))
    }

    private func classify(stderr: String, exitCode _: Int32) -> MetadataError {
        if stderr.isEmpty {
            return .ytDlpMissing
        }
        if stderr.contains("is not a valid URL") {
            return .badURL
        }
        if stderr.contains("Unsupported URL") {
            return .unsupported
        }
        if unavailableSignatures.contains(where: stderr.contains) {
            return .unavailable
        }
        let errorLine = firstErrorLine(stderr)
        if isNetworkFailure(stderr: stderr, errorLine: errorLine) {
            return .network
        }
        if errorLine.hasPrefix("ERROR:") {
            return .unknown(raw: errorLine)
        }
        return .unknown(raw: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func isNetworkFailure(stderr: String, errorLine: String) -> Bool {
        stderr.contains("Unable to download")
            && ProgressParser.classifyStderr(errorLine) == .networkDown
    }

    private func firstErrorLine(_ stderr: String) -> String {
        stderr
            .split(separator: "\n")
            .first { $0.hasPrefix("ERROR:") }
            .map(String.init) ?? stderr
    }

    private let unavailableSignatures = [
        "Video unavailable",
        "This video is unavailable",
        "This video is not available",
        "Private video",
        "blocked it in your country",
        "The web client only works when logged-in"
    ]
}
