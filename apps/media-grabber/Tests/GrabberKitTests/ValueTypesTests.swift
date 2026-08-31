@testable import GrabberKit
import TestSupport
import XCTest

final class ValueTypesTests: XCTestCase {
    private func snap(fraction: Double? = nil) -> JobSnapshot {
        JobSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            url: "https://archive.org/details/x", title: nil, state: .queued,
            progress: fraction.map { Progress(fraction: $0, downloadedBytes: 0) },
            kind: .video(maxHeight: 1080),
            durationSeconds: nil, extractor: nil, addedAt: Date(timeIntervalSince1970: 0),
            finishedAt: nil, destFolder: URL(fileURLWithPath: "/tmp"), outputFiles: [],
            sizeBytes: nil, actualQuality: nil, attempt: 0, cooldownUntil: nil,
            playerClientUsed: nil, playlistGroupID: nil, integrityVerdict: nil,
            availableActions: [.pause, .cancel, .forceStart, .remove, .openInBrowser]
        )
    }

    func test_progressChangeBreaksEquality() {
        XCTAssertNotEqual(snap(fraction: 0.25), snap(fraction: 0.60))
    }

    func test_allNilSnapshotIsValidAndEqual() {
        XCTAssertEqual(snap(), snap())
    }

    func test_queuedActionSet() {
        XCTAssertEqual(
            snap().availableActions,
            [.pause, .cancel, .forceStart, .remove, .openInBrowser]
        )
        XCTAssertFalse(snap().availableActions.contains(.retry))
    }

    func test_mediaType_casesAndRawValues() {
        XCTAssertEqual(MediaType.allCases, [.video, .audio])
        XCTAssertEqual(MediaType.video.rawValue, "video")
        XCTAssertEqual(MediaType.audio.rawValue, "audio")
    }

    func test_mediaType_codableRoundTrip() throws {
        for value in MediaType.allCases {
            let data = try JSONEncoder().encode(value)
            XCTAssertEqual(try JSONDecoder().decode(MediaType.self, from: data), value)
        }
    }

    func test_mediaMetadataDecodesExtractorFromJBlob() {
        let meta = MetadataProbe.decodeForTest(
            Fixture.text("ytdlp-J-video.json"),
            sourceURL: "https://x"
        )
        XCTAssertEqual(try meta.get().extractor, "archive.org")
    }
}
