@testable import GrabberKit
import TestSupport
import XCTest

enum EngineFixture {
    static let ytDlp = URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp")

    // Keep JobLog writes out of the real ~/Library/Logs during tests.
    static func scratchLogDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-joblogs-\(UUID().uuidString)")
    }

    // A fresh subdirectory per call so concurrent runs don't cross-contaminate .part/output lookups by title stem.
    static func scratchDestFolder() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-dest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func request(
        url: String = "https://archive.org/details/x",
        destFolder: URL = EngineFixture.scratchDestFolder()
    ) -> DownloadRequest {
        DownloadRequest(
            url: url,
            destFolder: destFolder,
            kind: .video(maxHeight: 1080),
            container: "mp4"
        )
    }

    static func engine(
        runner: FakeProcessRunner,
        probe: MetadataProbing,
        cap: Int = 3,
        preferences: Preferences? = nil,
        fileManager: FileManaging = FoundationFileManager(),
        resolverHome: URL? = nil,
        networkMonitor: (any NetworkPathMonitoring)? = nil,
        clock: FakeClock? = nil,
        tuning: EngineTuning = .default,
        maxAutoRetries: Int? = nil,
        potProvider: (any PotProviding)? = nil
    ) -> DownloadEngine {
        let prefs = preferences
            ?? Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        if let maxAutoRetries {
            prefs.maxAutoRetries = maxAutoRetries
        }
        return DownloadEngine(
            dependencies: EngineDependencies(
                runner: runner,
                fileManager: fileManager,
                probe: probe,
                envProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
                clock: clock ?? SystemClock(),
                ytDlpURL: ytDlp,
                jobLogDir: scratchLogDir(),
                debugFlags: EngineDebugFlags(concurrencyCapOverride: cap),
                tuning: tuning,
                cookieResolverHome: resolverHome,
                networkMonitor: networkMonitor,
                potProvider: potProvider ?? MissingPotProvider()
            ),
            preferences: prefs
        )
    }

    static func progressLine(_ percent: String, total: String = "1000") -> ProcessLine {
        .stdout("MG|\(percent)|1.00MiB/s|00:10|100|\(total)")
    }

    static func completingScript(_ lines: [ProcessLine] = []) -> FakeProcessRunner.Script {
        FakeProcessRunner.Script(lines: lines, exitCode: 0)
    }
}

extension XCTestCase {
    func submitJob(_ engine: DownloadEngine, _ req: DownloadRequest) async -> UUID {
        let result = await engine.submit(req, force: false, prefetchedMetadata: nil)
        guard case let .queued(id) = result else {
            XCTFail("expected .queued")
            return UUID()
        }
        return id
    }

    func expectState(
        _ collector: EventCollector,
        _ id: UUID,
        _ predicate: @escaping (JobState) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let reached = await collector.waitForState(id, predicate)
        XCTAssertTrue(reached, "job never reached expected state", file: file, line: line)
    }

    func isOrderedSubsequence(_ needle: [JobState], of haystack: [JobState]) -> Bool {
        var index = haystack.startIndex
        for target in needle {
            guard let found = haystack[index...].firstIndex(of: target) else { return false }
            index = haystack.index(after: found)
        }
        return true
    }
}
