@testable import GrabberKit
import XCTest

final class DownloadRequestTests: XCTestCase {
    private let dest = URL(fileURLWithPath: "/tmp/mg")

    func test_defaultOutputTemplate() {
        let request = DownloadRequest(
            url: "https://example.com/v",
            destFolder: dest,
            kind: .video(maxHeight: 1080)
        )
        XCTAssertEqual(request.outputTemplate, "%(title)s.%(ext)s")
    }

    func test_codableRoundTrip_video() throws {
        let request = DownloadRequest(
            url: "https://example.com/v",
            destFolder: dest,
            kind: .video(maxHeight: 720),
            container: "mp4"
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(DownloadRequest.self, from: data)
        XCTAssertEqual(decoded, request)
    }

    func test_codableRoundTrip_audio() throws {
        let request = DownloadRequest(
            url: "https://example.com/a",
            destFolder: dest,
            kind: .audio(codec: .mp3)
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(DownloadRequest.self, from: data)
        XCTAssertEqual(decoded, request)
    }

    func test_errorClass_unknownCarriesRaw() {
        let boom1 = ErrorClass.unknown(raw: "boom")
        let boom2 = ErrorClass.unknown(raw: "boom")
        let bang = ErrorClass.unknown(raw: "bang")
        XCTAssertEqual(boom1, boom2)
        XCTAssertNotEqual(boom1, bang)
    }

    @MainActor
    func test_jobStartsQueued() {
        let request = DownloadRequest(
            url: "https://example.com/v",
            destFolder: dest,
            kind: .video(maxHeight: 1080)
        )
        let job = DownloadJob(request: request)
        XCTAssertEqual(job.state, .queued)
        XCTAssertEqual(job.attempt, 0)
        XCTAssertNil(job.title)
        XCTAssertNil(job.progress)
        XCTAssertEqual(job.outputFiles, [])
    }

    func test_progressClampsFraction() {
        XCTAssertEqual(Progress(fraction: 1.5, downloadedBytes: 0).fraction, 1.0)
        XCTAssertEqual(Progress(fraction: -0.2, downloadedBytes: 0).fraction, 0.0)
    }
}
