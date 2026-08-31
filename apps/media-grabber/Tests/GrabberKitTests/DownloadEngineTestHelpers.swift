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

    static func request(
        url: String = "https://archive.org/details/x",
        destFolder: URL = URL(fileURLWithPath: NSTemporaryDirectory())
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
        probe: FakeMetadataProbe,
        cap: Int = 3,
        preferences: Preferences? = nil
    ) -> DownloadEngine {
        DownloadEngine(
            dependencies: EngineDependencies(
                runner: runner,
                probe: probe,
                envProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
                ytDlpURL: ytDlp,
                jobLogDir: scratchLogDir(),
                debugFlags: EngineDebugFlags(concurrencyCapOverride: cap)
            ),
            preferences: preferences
                ?? Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
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
