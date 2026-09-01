import Foundation
@testable import GrabberKit
@testable import MediaGrabber
import TestSupport

@MainActor
enum AppModelTestHelpers {
    static func makeModel(
        defaults: UserDefaults,
        logDirectory: URL,
        engine: FakeEngine = FakeEngine(),
        probe: FakeMetadataProbe = FakeMetadataProbe(.failure(.malformedOutput)),
        envReady: Bool = true,
        debugFlags: DebugFlags = DebugFlags(),
        revealSink: FakeRevealSink = FakeRevealSink(),
        openURLSink: FakeOpenURLSink = FakeOpenURLSink(),
        engineJobLogDir: URL? = nil,
        persistence: FakeQueuePersisting? = nil
    ) -> AppModel {
        AppModel(
            engine: engine,
            probe: probe,
            installer: OnboardingInstaller(
                probe: FakeEnvironmentProbe(ready: envReady),
                runner: NullRunner()
            ),
            prefs: Preferences(defaults: defaults),
            log: LogWriter(directory: logDirectory),
            envProbe: FakeEnvironmentProbe(ready: envReady),
            debugFlags: debugFlags,
            revealSink: revealSink,
            openURLSink: openURLSink,
            engineJobLogDir: engineJobLogDir ?? logDirectory,
            persistence: persistence
        )
    }

    static func meta(title: String = "Clip", url: String = "https://x/y") -> MediaMetadata {
        MediaMetadata(title: title, durationSeconds: 10, isPlaylist: false, sourceURL: url)
    }

    static func jobSnapshot(
        id: UUID = UUID(),
        outputFiles: [URL] = [],
        state: JobState = .completed
    ) -> JobSnapshot {
        JobSnapshot(
            id: id,
            url: "https://example.com/v",
            title: "Clip",
            state: state,
            progress: nil,
            kind: .video(maxHeight: 1080),
            durationSeconds: 10,
            extractor: "youtube",
            addedAt: Date(),
            finishedAt: Date(),
            destFolder: URL(fileURLWithPath: "/tmp"),
            outputFiles: outputFiles,
            sizeBytes: 100,
            actualQuality: "1080p",
            attempt: 1,
            cooldownUntil: nil,
            playerClientUsed: nil,
            playlistGroupID: nil,
            integrityVerdict: .passed,
            availableActions: [.reveal]
        )
    }

    static func logContainsEvent(_ event: String, in directory: URL) throws -> Bool {
        let logFile = directory.appendingPathComponent("app.log")
        guard FileManager.default.fileExists(atPath: logFile.path) else { return false }
        let text = try String(contentsOf: logFile, encoding: .utf8)
        return text.contains("\"event\":\"\(event)\"")
    }
}

struct NullRunner: ProcessRunning {
    func run(_: ProcessLaunch) -> ProcessExecution {
        let (stream, continuation) = AsyncStream<ProcessLine>.makeStream()
        continuation.finish()
        return ProcessExecution(lines: stream) { ProcessResult(exitCode: 0, wasCancelled: false) }
    }
}
