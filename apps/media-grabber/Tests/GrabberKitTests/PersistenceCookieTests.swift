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

    func test_encodedJob_carriesNoCookieKey() throws {
        let job = PersistedJob(id: UUID(), request: request(), state: .queued, addedAt: .init())
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(job), encoding: .utf8))
        XCTAssertFalse(json.lowercased().contains("cookie"))
    }

    func test_oldQueueJSON_withForceCookiesKey_stillDecodes() throws {
        let sample = PersistedJob(id: UUID(), request: request(), state: .queued, addedAt: .init())
        let encoded = try JSONEncoder().encode(sample)
        guard var dict = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            return XCTFail("expected a JSON object")
        }
        dict["forceCookies"] = true
        let legacy = try JSONSerialization.data(withJSONObject: dict)
        XCTAssertEqual(try JSONDecoder().decode(PersistedJob.self, from: legacy), sample)
    }
}
