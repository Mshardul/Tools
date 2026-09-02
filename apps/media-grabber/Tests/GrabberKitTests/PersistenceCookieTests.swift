@testable import GrabberKit
import XCTest

final class PersistenceCookieTests: XCTestCase {
    private func request() -> DownloadRequest {
        DownloadRequest(
            url: "https://archive.org/x",
            destFolder: URL(fileURLWithPath: "/tmp/out"),
            kind: .video(maxHeight: 1080),
            container: "mp4",
            filenameTemplate: "%(title)s.%(ext)s"
        )
    }

    func test_forceCookiesTrue_roundTrips() throws {
        let job = PersistedJob(
            id: UUID(),
            request: request(),
            state: .failed(reason: "cookie_read_failed"),
            forceCookies: true,
            addedAt: .init()
        )
        let data = try JSONEncoder().encode(job)
        XCTAssertEqual(try JSONDecoder().decode(PersistedJob.self, from: data).forceCookies, true)
    }

    func test_oldQueueJSON_withoutForceCookies_decodesToFalse() throws {
        let sample = PersistedJob(id: UUID(), request: request(), state: .queued, addedAt: .init())
        let encoded = try JSONEncoder().encode(sample)
        guard var dict = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            return XCTFail("expected a JSON object")
        }
        dict.removeValue(forKey: "forceCookies")
        let stripped = try JSONSerialization.data(withJSONObject: dict)
        XCTAssertEqual(
            try JSONDecoder().decode(PersistedJob.self, from: stripped).forceCookies,
            false
        )
    }

    func test_downloadJob_restoresForceCookies() {
        let persisted = PersistedJob(
            id: UUID(),
            request: request(),
            state: .queued,
            forceCookies: true,
            addedAt: .init()
        )
        XCTAssertTrue(DownloadEngine.downloadJob(from: persisted).forceCookies)
    }
}
