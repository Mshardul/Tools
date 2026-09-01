import Foundation

public struct MediaMetadata: Sendable, Equatable {
    public let title: String
    public let durationSeconds: Int?
    public let isPlaylist: Bool
    public let sourceURL: String
    public let extractor: String?

    public init(
        title: String,
        durationSeconds: Int?,
        isPlaylist: Bool,
        sourceURL: String,
        extractor: String? = nil
    ) {
        self.title = title
        self.durationSeconds = durationSeconds
        self.isPlaylist = isPlaylist
        self.sourceURL = sourceURL
        self.extractor = extractor
    }
}

public enum MetadataError: Error, Sendable, Equatable {
    case badURL
    case unsupported
    case unavailable
    case network
    case ytDlpMissing
    case launchFailed
    case malformedOutput
    case botCheck
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
            arguments: ["-J", "--no-warnings", "--no-playlist", "--no-update", url]
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
        return Self.decode(stdout, sourceURL: url)
    }

    static func decodeForTest(
        _ stdout: String,
        sourceURL: String
    ) -> Result<MediaMetadata, MetadataError> {
        decode(stdout, sourceURL: sourceURL)
    }

    private static func decode(
        _ stdout: String,
        sourceURL: String
    ) -> Result<MediaMetadata, MetadataError> {
        struct Payload: Decodable {
            let title: String?
            let duration: Double?
            let extractor: String?
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
            sourceURL: sourceURL,
            extractor: payload.extractor
        ))
    }

    private func classify(stderr: String, exitCode: Int32) -> MetadataError {
        if exitCode == 127, stderr.contains("launch failed:") {
            return .launchFailed
        }
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
        if isBotCheck(stderr) {
            return .botCheck
        }
        if errorLine.hasPrefix("ERROR:") {
            return .unknown(raw: errorLine)
        }
        return .unknown(raw: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func isBotCheck(_ stderr: String) -> Bool {
        botCheckSignatures.contains { stderr.localizedCaseInsensitiveContains($0) }
    }

    private let botCheckSignatures = [
        "page needs to be reloaded",
        "confirm you're not a bot",
        "Sign in to confirm",
        "unable to extract uploader id",
        "HTTP Error 403",
        "This content isn't available, try again later"
    ]

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

    // The shared strings come from the one ErrorSignatures table so the probe-side and
    // download-side classifiers agree; "logged-in" is probe-only, no download equivalent.
    private var unavailableSignatures: [String] {
        Self.sharedUnavailableSignatures + ["The web client only works when logged-in"]
    }

    private static let sharedUnavailableSignatures: [String] = ErrorSignatures.table
        .filter { entry in
            switch entry.errorClass {
            case .unavailable, .private, .geoBlocked: true
            default: false
            }
        }
        .flatMap(\.substrings)
}
