import Foundation

public struct IntegrityResult: Sendable, Equatable {
    public let verdict: IntegrityVerdict
    // "720p" for video, nil for audio or an unreadable stream.
    public let actualQuality: String?

    public init(verdict: IntegrityVerdict, actualQuality: String?) {
        self.verdict = verdict
        self.actualQuality = actualQuality
    }
}

// An ffprobe of the finalized file: a materially short duration fails the job; a broken or missing probe is .skipped.
public struct IntegrityCheck: Sendable {
    private let runner: ProcessRunning
    private let ffprobeURL: URL?
    private let isExecutable: @Sendable (URL) -> Bool

    public init(
        runner: ProcessRunning,
        ffprobeURL: URL?,
        isExecutable: @escaping @Sendable (URL) -> Bool = { url in
            FileManager.default.isExecutableFile(atPath: url.path)
        }
    ) {
        self.runner = runner
        self.ffprobeURL = ffprobeURL
        self.isExecutable = isExecutable
    }

    public func verify(file: URL, expectedDurationSeconds: Int?) async -> IntegrityResult {
        guard let ffprobeURL, isExecutable(ffprobeURL) else {
            return IntegrityResult(
                verdict: .skipped(reason: "ffprobe unavailable"),
                actualQuality: nil
            )
        }
        let execution = runner.run(ProcessLaunch(
            executableURL: ffprobeURL,
            arguments: [
                "-v", "quiet",
                "-print_format", "json",
                "-show_format", "-show_streams",
                file.path
            ]
        ))
        var stdout = ""
        for await line in execution.lines {
            if case let .stdout(text) = line {
                stdout += text + "\n"
            }
        }
        let result = await execution.result()
        guard result.exitCode == 0, let probe = Self.parse(stdout) else {
            return IntegrityResult(verdict: .skipped(reason: "ffprobe failed"), actualQuality: nil)
        }
        let quality = probe.height.map { "\($0)p" }
        guard let expected = expectedDurationSeconds else {
            return IntegrityResult(
                verdict: .skipped(reason: "no expected duration"),
                actualQuality: quality
            )
        }
        return IntegrityResult(
            verdict: Self.durationVerdict(actual: probe.duration, expected: expected),
            actualQuality: quality
        )
    }

    private struct Probe {
        var duration: Double
        var height: Int?
    }

    private static func parse(_ stdout: String) -> Probe? {
        struct Stream: Decodable {
            // swiftlint:disable:next identifier_name
            let codec_type: String?
            let height: Int?
        }
        struct Format: Decodable {
            let duration: String?
        }
        struct Payload: Decodable {
            let format: Format?
            let streams: [Stream]?
        }
        guard
            let data = stdout.data(using: .utf8),
            let payload = try? JSONDecoder().decode(Payload.self, from: data),
            let durationString = payload.format?.duration,
            let duration = Double(durationString)
        else {
            return nil
        }
        let height = payload.streams?.first { $0.codec_type == "video" }?.height
        return Probe(duration: duration, height: height)
    }

    // Materially short means under 95% of expected AND over 10s absolute, so trim drift passes on short and long clips.
    private static func durationVerdict(actual: Double, expected: Int) -> IntegrityVerdict {
        let expectedDouble = Double(expected)
        let gap = expectedDouble - actual
        let materiallyShort = actual < expectedDouble * 0.95 && gap > 10
        if materiallyShort {
            return .failed(reason: "recording is \(Int(gap))s short")
        }
        return .passed
    }
}
