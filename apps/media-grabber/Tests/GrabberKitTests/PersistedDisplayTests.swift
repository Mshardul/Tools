@testable import GrabberKit
import XCTest

final class PersistedDisplayTests: XCTestCase {
    func test_legacyJobWithoutDisplayFacts_decodesEmpty() throws {
        let saved = try sample()
        let data = try JSONEncoder().encode(saved)
        let object = try JSONSerialization.jsonObject(with: data)
        guard var fields = object as? [String: Any] else {
            return XCTFail("expected a JSON object")
        }
        for key in [
            "sizeBytes", "actualQuality", "progressFraction", "downloadedBytes",
            "totalBytes", "outputFiles", "playerClientUsed"
        ] {
            fields.removeValue(forKey: key)
        }
        let legacy = try JSONSerialization.data(withJSONObject: fields)
        let decoded = try JSONDecoder().decode(PersistedJob.self, from: legacy)
        XCTAssertNil(decoded.sizeBytes)
        XCTAssertNil(decoded.actualQuality)
        XCTAssertNil(decoded.progressFraction)
        XCTAssertEqual(decoded.outputFiles, [])
        XCTAssertNil(decoded.playerClientUsed)
    }

    func test_displayFactsRoundTrip() throws {
        let file = URL(fileURLWithPath: "/tmp/out/Clip.mp4")
        let saved = try PersistedJob(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000009")),
            request: request(),
            title: "Clip",
            state: .completed,
            addedAt: Date(timeIntervalSince1970: 1),
            finishedAt: Date(timeIntervalSince1970: 2),
            sizeBytes: 2048,
            actualQuality: "720p",
            progressFraction: 1,
            downloadedBytes: 2048,
            totalBytes: 2048,
            outputFiles: [file],
            playerClientUsed: "web"
        )
        let decoded = try JSONDecoder().decode(PersistedJob.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(decoded, saved)
    }

    private func sample() throws -> PersistedJob {
        try PersistedJob(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            request: request(),
            title: "Clip",
            state: .completed,
            addedAt: Date(timeIntervalSince1970: 1),
            finishedAt: Date(timeIntervalSince1970: 5)
        )
    }

    private func request() -> DownloadRequest {
        DownloadRequest(
            url: "https://archive.org/x",
            destFolder: URL(fileURLWithPath: "/tmp/out"),
            kind: .video(maxHeight: 1080),
            container: "mp4"
        )
    }
}
