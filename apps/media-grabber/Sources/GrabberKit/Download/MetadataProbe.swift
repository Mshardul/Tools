import Foundation

public struct MediaMetadata: Sendable, Equatable {
    public let title: String
    public let durationSeconds: Int?
    public let isPlaylist: Bool
    public let sourceURL: String
    public let extractor: String?
    public let formatAvailability: FormatAvailability
    public let videoHeights: [Int]
    public let audioTracks: [AudioTrack]

    public init(
        title: String,
        durationSeconds: Int?,
        isPlaylist: Bool,
        sourceURL: String,
        extractor: String? = nil,
        formatAvailability: FormatAvailability = .unknown,
        videoHeights: [Int] = [],
        audioTracks: [AudioTrack] = []
    ) {
        self.title = title
        self.durationSeconds = durationSeconds
        self.isPlaylist = isPlaylist
        self.sourceURL = sourceURL
        self.extractor = extractor
        self.formatAvailability = formatAvailability
        self.videoHeights = videoHeights
        self.audioTracks = audioTracks
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
    case hostBlocked
    case unknown(raw: String)
}

public protocol MetadataProbing: Sendable {
    func probe(_ url: String, context: ExtractorContext) async -> Result<MediaMetadata, MetadataError>
    func probePlaylist(_ url: String, context: ExtractorContext) async -> Result<PlaylistDump, MetadataError>
}

public extension MetadataProbing {
    func probe(_ url: String) async -> Result<MediaMetadata, MetadataError> {
        await probe(url, context: .none)
    }
}

public actor MetadataProbe: MetadataProbing {
    private let ytDlpURL: URL
    private let runner: ProcessRunning
    private let bucket: any MetadataTokenBucketing

    // Actors are reentrant across `await`, so chain probes explicitly to serialize.
    private var tail: Task<Void, Never> = Task {}

    public init(
        ytDlpURL: URL,
        runner: ProcessRunning = ProcessRunner(),
        bucket: any MetadataTokenBucketing = UnlimitedMetadataTokenBucket()
    ) {
        self.ytDlpURL = ytDlpURL
        self.runner = runner
        self.bucket = bucket
    }

    public func probe(
        _ url: String,
        context: ExtractorContext = .none
    ) async -> Result<MediaMetadata, MetadataError> {
        await enqueue {
            await self.runProbe(url, context: context)
        }
    }

    public func probePlaylist(
        _ url: String,
        context: ExtractorContext = .none
    ) async -> Result<PlaylistDump, MetadataError> {
        await enqueue {
            await self.runPlaylistProbe(url, context: context)
        }
    }

    private func enqueue<Output: Sendable>(
        _ operation: @escaping @Sendable () async -> Result<Output, MetadataError>
    ) async -> Result<Output, MetadataError> {
        let predecessor = tail
        let work = Task { () -> Result<Output, MetadataError> in
            await predecessor.value
            await bucket.acquire()
            if Task.isCancelled {
                return .failure(.malformedOutput)
            }
            return await operation()
        }
        tail = Task { _ = await work.value }
        return await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }

    private func runProbe(
        _ url: String,
        context: ExtractorContext
    ) async -> Result<MediaMetadata, MetadataError> {
        let arguments = ["-J", "--no-warnings", "--no-playlist", "--no-update"]
            + YtDlpArguments.extractorFlags(context: context)
            + [url]
        let output = await runYtDlp(arguments: arguments)

        if output.result.wasCancelled || Task.isCancelled {
            return .failure(.malformedOutput)
        }
        guard output.result.exitCode == 0 else {
            return .failure(classify(stderr: output.stderr, exitCode: output.result.exitCode))
        }
        return Self.decode(output.stdout, sourceURL: url)
    }

    private func runPlaylistProbe(
        _ url: String,
        context: ExtractorContext
    ) async -> Result<PlaylistDump, MetadataError> {
        let arguments = ["-J", "--flat-playlist", "--no-warnings", "--no-update"]
            + YtDlpArguments.extractorFlags(context: context)
            + [url]
        let output = await runYtDlp(arguments: arguments)

        if output.result.wasCancelled || Task.isCancelled {
            return .failure(.malformedOutput)
        }
        guard output.result.exitCode == 0 else {
            return .failure(classify(stderr: output.stderr, exitCode: output.result.exitCode))
        }
        return PlaylistDump.decode(output.stdout, pasteURL: url)
    }

    private func runYtDlp(arguments: [String]) async -> ProbeProcessOutput {
        let execution = runner.run(ProcessLaunch(
            executableURL: ytDlpURL,
            arguments: arguments
        ))
        let textTask = Task {
            await collectText(from: execution.lines)
        }
        let result = await execution.result()
        let text = await textTask.value
        return ProbeProcessOutput(
            stdout: text.stdout,
            stderr: text.stderr,
            result: result
        )
    }

    private func collectText(from lines: AsyncStream<ProcessLine>) async -> ProbeTextOutput {
        var stdout = ""
        var stderr = ""
        for await line in lines {
            switch line {
            case let .stdout(text): stdout += text + "\n"
            case let .stderr(text): stderr += text + "\n"
            }
        }
        return ProbeTextOutput(
            stdout: stdout,
            stderr: stderr
        )
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
        guard
            let data = stdout.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let title = object["title"] as? String
        else {
            return .failure(.malformedOutput)
        }
        let parsed = FormatCatalog.parseJSONObject(object)
        return .success(MediaMetadata(
            title: title,
            durationSeconds: durationSeconds(object),
            isPlaylist: (object["_type"] as? String) == "playlist",
            sourceURL: sourceURL,
            extractor: object["extractor"] as? String,
            formatAvailability: parsed.availability,
            videoHeights: parsed.videoHeights,
            audioTracks: parsed.audioTracks
        ))
    }

    private static func durationSeconds(_ object: [String: Any]) -> Int? {
        guard let value = object["duration"] else { return nil }
        if let number = value as? Double {
            return Int(number.rounded())
        }
        if let number = value as? Int {
            return number
        }
        if let number = value as? NSNumber {
            return Int(number.doubleValue.rounded())
        }
        return nil
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
        if let matched = ErrorSignatures.firstMatch(in: stderr), case .botCheck = matched {
            return .botCheck
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

    // Shared strings from the ErrorSignatures table plus one probe-only "logged-in" case with no download equivalent.
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

private struct ProbeProcessOutput: Sendable {
    var stdout: String
    var stderr: String
    var result: ProcessResult
}

private struct ProbeTextOutput: Sendable {
    var stdout: String
    var stderr: String
}
