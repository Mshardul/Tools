@testable import GrabberKit
import XCTest

final class ProgressParserTests: XCTestCase {
    // MARK: - Progress lines

    func test_progressLine_midDownload() throws {
        let event = ProgressParser.parseStdout("MG| 42.3%|1.23MiB/s|00:37|1290000|3050000")
        guard case let .progress(progress) = event else {
            return XCTFail("expected .progress, got \(event)")
        }
        XCTAssertEqual(progress.fraction, 0.423, accuracy: 0.0005)
        XCTAssertEqual(try XCTUnwrap(progress.speedBytesPerSec), 1_289_748, accuracy: 2000)
        XCTAssertEqual(progress.etaSeconds, 37)
        XCTAssertEqual(progress.downloadedBytes, 1_290_000)
        XCTAssertEqual(progress.totalBytes, 3_050_000)
    }

    func test_progressLine_unknownSpeedAndEta() {
        let event = ProgressParser.parseStdout("MG|  0.0%|Unknown B/s|Unknown|0|NA")
        guard case let .progress(progress) = event else {
            return XCTFail("expected .progress, got \(event)")
        }
        XCTAssertEqual(progress.fraction, 0)
        XCTAssertNil(progress.speedBytesPerSec)
        XCTAssertNil(progress.etaSeconds)
        XCTAssertNil(progress.totalBytes)
    }

    func test_progressLine_hundredPercent() {
        let event = ProgressParser.parseStdout("MG|100.0%|  11.81MiB/s|00:00|96645673|96645673")
        guard case let .progress(progress) = event else {
            return XCTFail("expected .progress, got \(event)")
        }
        XCTAssertEqual(progress.fraction, 1.0)
    }

    func test_progressLine_hoursEta() {
        let event = ProgressParser.parseStdout("MG|  0.0%|  13.90KiB/s|01:53:10|1024|96645673")
        guard case let .progress(progress) = event else {
            return XCTFail("expected .progress, got \(event)")
        }
        XCTAssertEqual(progress.etaSeconds, 1 * 3600 + 53 * 60 + 10)
    }

    // MARK: - Post-processing / ignored

    func test_postProcessingLine_merger() {
        XCTAssertEqual(
            ProgressParser.parseStdout(#"[Merger] Merging formats into "x.mp4""#),
            .postProcessing
        )
    }

    func test_postProcessingLine_extractAudio() {
        XCTAssertEqual(
            ProgressParser.parseStdout("[ExtractAudio] Destination: /tmp/mg.m4a"),
            .postProcessing
        )
    }

    func test_postProcessingLine_deletingOriginal() {
        XCTAssertEqual(
            ProgressParser.parseStdout("Deleting original file /tmp/mg.webm (pass -k to keep)"),
            .postProcessing
        )
    }

    func test_plainDownloadLine_ignored() {
        XCTAssertEqual(
            ProgressParser.parseStdout("[download] Destination: x.f137.mp4"),
            .ignored
        )
    }

    func test_captureOutputPath_downloadDestination() {
        let url = ProgressParser.captureOutputPath(
            from: "[download] Destination: /tmp/RASTAFARIANESIMO.mp4"
        )
        XCTAssertEqual(url?.path, "/tmp/RASTAFARIANESIMO.mp4")
    }

    func test_captureOutputPath_mergerDestination() {
        let url = ProgressParser.captureOutputPath(
            from: #"[Merger] Merging formats into "/tmp/Clip.mp4""#
        )
        XCTAssertEqual(url?.path, "/tmp/Clip.mp4")
    }

    func test_captureOutputPath_extractAudio() {
        let url = ProgressParser.captureOutputPath(
            from: "[ExtractAudio] Destination: /tmp/mg.m4a"
        )
        XCTAssertEqual(url?.path, "/tmp/mg.m4a")
    }

    // MARK: - stderr classification

    func test_stderr_networkError() {
        let error = ProgressParser.classifyStderr(
            "ERROR: [generic] Unable to download webpage: Failed to resolve 'x' "
                + "([Errno 8] nodename nor servname provided, or not known)"
        )
        XCTAssertEqual(error, .networkDown)
    }

    func test_stderr_networkError_getaddrinfo() {
        let error = ProgressParser.classifyStderr(
            "ERROR: Unable to download webpage (caused by getaddrinfo failed)"
        )
        XCTAssertEqual(error, .networkDown)
    }

    func test_stderr_genericError() {
        let error = ProgressParser.classifyStderr("ERROR: Video unavailable")
        XCTAssertEqual(error, .unknown(raw: "ERROR: Video unavailable"))
    }

    func test_stderr_nonError_returnsNil() {
        XCTAssertNil(
            ProgressParser.classifyStderr("[info] Downloading 1 format(s): 137+140")
        )
    }

    // MARK: - Fixture-driven

    func test_fixtureRun_producesExpectedEventSequence() throws {
        let text = try fixture("ytdlp-video-run", "txt")
        var fractions: [Double] = []
        var sawPostProcessing = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            switch ProgressParser.parseStdout(String(line)) {
            case let .progress(progress):
                fractions.append(progress.fraction)
            case .postProcessing:
                sawPostProcessing = true
            case .ignored:
                break
            }
        }
        XCTAssertFalse(fractions.isEmpty)
        XCTAssertEqual(fractions.last, 1.0)
        XCTAssertEqual(fractions, fractions.sorted(), "fractions must be monotonic")
        XCTAssertTrue(sawPostProcessing)
    }

    func test_fixtureNetworkError_classifiesNetworkDown() throws {
        let text = try fixture("ytdlp-network-error", "txt")
        let classified = text
            .split(separator: "\n")
            .compactMap { ProgressParser.classifyStderr(String($0)) }
        XCTAssertTrue(classified.contains(.networkDown))
    }

    func test_fixtureGenericError_classifiesUnknown() throws {
        let text = try fixture("ytdlp-generic-error", "txt")
        let classified = text
            .split(separator: "\n")
            .compactMap { ProgressParser.classifyStderr(String($0)) }
        XCTAssertTrue(classified.contains {
            if case .unknown = $0 {
                true
            } else {
                false
            }
        })
        XCTAssertFalse(classified.contains(.networkDown))
    }

    func test_malformedProgressLine_neverCrashes() {
        for line in ["MG|garbage", "MG|", "MG|||||", "MG| |x|y|z|w"] {
            let event = ProgressParser.parseStdout(line)
            switch event {
            case .ignored, .progress:
                break
            case .postProcessing:
                XCTFail("unexpected .postProcessing for \(line)")
            }
        }
    }

    // MARK: - Helpers

    private func fixture(_ name: String, _ ext: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext))
        return try String(contentsOf: url, encoding: .utf8)
    }
}
